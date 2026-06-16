'use client'

import { useState, useMemo, useEffect } from 'react'
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseUnits, parseEther, formatUnits, formatEther, maxUint256 } from 'viem'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'

const ERC20_ABI = [
  { name: 'approve',   type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view',       inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'balanceOf', type: 'function', stateMutability: 'view',       inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
] as const

function safeParseUnits(value: string, decimals: number): bigint | undefined {
  try {
    const n = parseFloat(value)
    if (!value || isNaN(n) || n <= 0) return undefined
    return parseUnits(value as `${number}`, decimals)
  } catch {
    return undefined
  }
}

function formatTokenOut(amount: bigint, decimals: number): string {
  const v = parseFloat(formatUnits(amount, decimals))
  if (v >= 1_000_000) return `${(v / 1_000_000).toFixed(2)}M`
  if (v >= 1_000)     return `${(v / 1_000).toFixed(2)}K`
  if (v >= 1)         return v.toFixed(4)
  return v.toFixed(6)
}

interface Props {
  tokenAddress: `0x${string}`
  tokenSymbol: string
  onTradeSuccess?: () => void
}

export function BondingTradePanel({ tokenAddress, tokenSymbol, onTradeSuccess }: Props) {
  const { address } = useAccount()
  const [usdcAmount, setUsdcAmount] = useState('')
  const [tokenAmount, setTokenAmount] = useState('')
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()
  const [confirmed, setConfirmed] = useState(false)
  const [refreshIn, setRefreshIn] = useState(0)
  const [error, setError] = useState<string | null>(null)

  const { writeContractAsync, isPending } = useWriteContract()

  // Balances + allowance
  const { data: usdcBalance } = useReadContract({
    address: ADDRESSES.MockUSDC, abi: ERC20_ABI, functionName: 'balanceOf',
    args: address ? [address] : undefined, query: { enabled: !!address },
  })
  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: ADDRESSES.MockUSDC, abi: ERC20_ABI, functionName: 'allowance',
    args: address ? [address, ADDRESSES.GradPadFactory] : undefined, query: { enabled: !!address },
  })
  const { data: tokenBalance } = useReadContract({
    address: tokenAddress, abi: ERC20_ABI, functionName: 'balanceOf',
    args: address ? [address] : undefined, query: { enabled: !!address },
  })

  // Quote inputs — safely parsed
  const buyAmountIn  = useMemo(() => safeParseUnits(usdcAmount, 6),   [usdcAmount])
  const sellAmountIn = useMemo(() => safeParseUnits(tokenAmount, 18), [tokenAmount])

  // Buy quote: getTokensOut(token, assetIn) → tokensOut
  const { data: tokensOutQuote } = useReadContract({
    address: ADDRESSES.GradPadFactory, abi: ABIS.GradPadFactory, functionName: 'getTokensOut',
    args: [tokenAddress, buyAmountIn ?? BigInt(0)],
    query: { enabled: !!buyAmountIn },
  })

  // Sell quote: getAssetOut(token, tokenIn) → assetOut
  const { data: assetOutQuote } = useReadContract({
    address: ADDRESSES.GradPadFactory, abi: ABIS.GradPadFactory, functionName: 'getAssetOut',
    args: [tokenAddress, sellAmountIn ?? BigInt(0)],
    query: { enabled: !!sellAmountIn },
  })

  // Receipt watching
  const { data: receipt } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: !!txHash && !confirmed },
  })

  // On confirmation: start countdown + notify parent
  useEffect(() => {
    if (!receipt || confirmed) return
    setConfirmed(true)
    setRefreshIn(12)
    onTradeSuccess?.()
  }, [receipt, confirmed, onTradeSuccess])

  // Countdown to reset panel
  useEffect(() => {
    if (refreshIn <= 0) return
    const t = setTimeout(() => {
      setRefreshIn(n => {
        if (n <= 1) {
          setTxHash(undefined)
          setConfirmed(false)
        }
        return n - 1
      })
    }, 1000)
    return () => clearTimeout(t)
  }, [refreshIn])

  const usdcBalanceBigInt  = typeof usdcBalance  === 'bigint' ? usdcBalance  : BigInt(0)
  const tokenBalanceBigInt = typeof tokenBalance === 'bigint' ? tokenBalance : BigInt(0)
  const usdcAllowanceBigInt = typeof usdcAllowance === 'bigint' ? usdcAllowance : BigInt(0)

  const isConfirming = !!txHash && !confirmed
  const isDone       = confirmed && refreshIn > 0

  async function handleBuy() {
    if (!usdcAmount || !address || !buyAmountIn) return
    setError(null)
    try {
      if (usdcAllowanceBigInt < buyAmountIn) {
        await writeContractAsync({
          address: ADDRESSES.MockUSDC, abi: ERC20_ABI, functionName: 'approve',
          args: [ADDRESSES.GradPadFactory, maxUint256],
        })
        await refetchUsdcAllowance()
      }
      const hash = await writeContractAsync({
        address: ADDRESSES.GradPadFactory, abi: ABIS.GradPadFactory, functionName: 'buyGPToken',
        args: [tokenAddress, buyAmountIn, address, BigInt(0)],
      })
      setTxHash(hash)
      setUsdcAmount('')
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message.slice(0, 120) : 'Transaction failed')
    }
  }

  async function handleSell() {
    if (!tokenAmount || !address || !sellAmountIn) return
    setError(null)
    try {
      await writeContractAsync({
        address: tokenAddress, abi: ERC20_ABI, functionName: 'approve',
        args: [ADDRESSES.GradPadFactory, maxUint256],
      })
      const hash = await writeContractAsync({
        address: ADDRESSES.GradPadFactory, abi: ABIS.GradPadFactory, functionName: 'sellGPToken',
        args: [tokenAddress, sellAmountIn, address, BigInt(0)],
      })
      setTxHash(hash)
      setTokenAmount('')
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message.slice(0, 120) : 'Transaction failed')
    }
  }

  return (
    <div
      className="rounded-2xl p-5 space-y-4"
      style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
    >
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-white">Trade</h2>
        <span
          className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded"
          style={{ background: 'rgba(251,191,36,0.12)', border: '1px solid rgba(251,191,36,0.2)', color: '#fbbf24' }}
        >
          Bonding Curve
        </span>
      </div>

      {/* Confirming state */}
      {isConfirming && (
        <div className="py-5 text-center space-y-3">
          <div
            className="mx-auto h-9 w-9 rounded-full animate-spin"
            style={{ border: '2px solid rgba(251,191,36,0.15)', borderTopColor: '#fbbf24' }}
          />
          <p className="text-sm font-medium text-white">Confirming on-chain...</p>
          {txHash && (
            <a href={`https://basescan.org/tx/${txHash}`} target="_blank" rel="noopener noreferrer"
              className="text-xs hover:underline" style={{ color: '#fbbf24' }}>
              View on BaseScan ↗
            </a>
          )}
        </div>
      )}

      {/* Done state */}
      {isDone && (
        <div className="py-5 text-center space-y-3">
          <div
            className="mx-auto h-9 w-9 rounded-full flex items-center justify-center"
            style={{ background: 'rgba(16,185,129,0.12)', border: '1px solid rgba(16,185,129,0.3)' }}
          >
            <div className="h-4 w-4 rounded-full" style={{ background: '#34d399' }} />
          </div>
          <p className="text-sm font-medium text-white">Trade confirmed!</p>
          <p className="text-xs text-muted-foreground">
            Refreshing stats in {refreshIn}s...
          </p>
          {txHash && (
            <a href={`https://basescan.org/tx/${txHash}`} target="_blank" rel="noopener noreferrer"
              className="text-xs hover:underline" style={{ color: '#34d399' }}>
              View on BaseScan ↗
            </a>
          )}
        </div>
      )}

      {/* Normal trade UI */}
      {!isConfirming && !isDone && (
        <Tabs defaultValue="buy">
          <TabsList className="w-full" style={{ background: 'rgba(255,255,255,0.05)' }}>
            <TabsTrigger value="buy" className="flex-1">Buy</TabsTrigger>
            <TabsTrigger value="sell" className="flex-1">Sell</TabsTrigger>
          </TabsList>

          <TabsContent value="buy" className="space-y-3 pt-3">
            <div className="space-y-1">
              <div className="flex justify-between text-xs text-muted-foreground">
                <span>You pay (mUSDC)</span>
                <span>Balance: {parseFloat(formatUnits(usdcBalanceBigInt, 6)).toFixed(2)}</span>
              </div>
              <Input
                type="number"
                value={usdcAmount}
                onChange={e => setUsdcAmount(e.target.value)}
                placeholder="0.0"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              />
              {tokensOutQuote !== undefined && buyAmountIn && (
                <p className="text-xs pt-0.5" style={{ color: '#9ca3af' }}>
                  You receive: ~{formatTokenOut(tokensOutQuote as bigint, 18)} {tokenSymbol}
                </p>
              )}
            </div>
            <Button
              className="w-full font-bold"
              onClick={handleBuy}
              disabled={!usdcAmount || isPending || !address}
              style={{
                background: !usdcAmount || isPending || !address
                  ? 'rgba(255,255,255,0.06)'
                  : 'linear-gradient(90deg, #d97706, #fbbf24)',
                color: !usdcAmount || isPending || !address ? '#6b7280' : '#0c0a06',
                border: 'none',
              }}
            >
              {isPending ? 'Confirm in wallet...' : `Buy ${tokenSymbol}`}
            </Button>
          </TabsContent>

          <TabsContent value="sell" className="space-y-3 pt-3">
            <div className="space-y-1">
              <div className="flex justify-between text-xs text-muted-foreground">
                <span>You sell ({tokenSymbol})</span>
                <span>Balance: {parseFloat(formatEther(tokenBalanceBigInt)).toFixed(4)}</span>
              </div>
              <Input
                type="number"
                value={tokenAmount}
                onChange={e => setTokenAmount(e.target.value)}
                placeholder="0.0"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              />
              {assetOutQuote !== undefined && sellAmountIn && (
                <p className="text-xs pt-0.5" style={{ color: '#9ca3af' }}>
                  You receive: ~{parseFloat(formatUnits(assetOutQuote as bigint, 6)).toFixed(4)} mUSDC
                </p>
              )}
            </div>
            <Button
              className="w-full font-bold"
              onClick={handleSell}
              disabled={!tokenAmount || isPending || !address}
              style={{
                background: !tokenAmount || isPending || !address
                  ? 'rgba(255,255,255,0.06)'
                  : '#ef4444',
                color: !tokenAmount || isPending || !address ? '#6b7280' : 'white',
                border: 'none',
              }}
            >
              {isPending ? 'Confirm in wallet...' : `Sell ${tokenSymbol}`}
            </Button>
          </TabsContent>
        </Tabs>
      )}

      {error && <p className="text-xs text-red-400 break-words">{error}</p>}
    </div>
  )
}
