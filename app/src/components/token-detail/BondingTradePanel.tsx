'use client'

import { useState } from 'react'
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseUnits, parseEther, formatUnits, formatEther, maxUint256 } from 'viem'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'

// Minimal ERC-20 ABI for approve + allowance + balanceOf
const ERC20_ABI = [
  { name: 'approve',   type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view',       inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'balanceOf', type: 'function', stateMutability: 'view',       inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
] as const

interface Props {
  tokenAddress: `0x${string}`
  tokenSymbol: string
}

export function BondingTradePanel({ tokenAddress, tokenSymbol }: Props) {
  const { address } = useAccount()
  const [usdcAmount, setUsdcAmount] = useState('')
  const [tokenAmount, setTokenAmount] = useState('')
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined)
  const [error, setError] = useState<string | null>(null)

  const { writeContractAsync, isPending } = useWriteContract()

  // USDC balance
  const { data: usdcBalance } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  // USDC allowance for GradPadFactory
  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, ADDRESSES.GradPadFactory] : undefined,
    query: { enabled: !!address },
  })

  // GP token balance for sell
  const { data: tokenBalance } = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: receipt } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: !!txHash },
  })

  // Suppress unused variable warning — receipt used for side-effect awareness
  void receipt

  const usdcBalanceBigInt = typeof usdcBalance === 'bigint' ? usdcBalance : BigInt(0)
  const tokenBalanceBigInt = typeof tokenBalance === 'bigint' ? tokenBalance : BigInt(0)
  const usdcAllowanceBigInt = typeof usdcAllowance === 'bigint' ? usdcAllowance : BigInt(0)

  // GradPadFactory.buyGPToken(token, assetAmountIn, to, minTokensOut)
  async function handleBuy() {
    if (!usdcAmount || !address) return
    setError(null)
    try {
      const amountIn = parseUnits(usdcAmount, 6) // USDC has 6 decimals

      // Approve if allowance insufficient
      if (usdcAllowanceBigInt < amountIn) {
        await writeContractAsync({
          address: ADDRESSES.MockUSDC,
          abi: ERC20_ABI,
          functionName: 'approve',
          args: [ADDRESSES.GradPadFactory, maxUint256],
        })
        await refetchUsdcAllowance()
      }

      const hash = await writeContractAsync({
        address: ADDRESSES.GradPadFactory,
        abi: ABIS.GradPadFactory,
        functionName: 'buyGPToken',
        args: [tokenAddress, amountIn, address, BigInt(0)],
      })
      setTxHash(hash)
      setUsdcAmount('')
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Transaction failed')
    }
  }

  // GradPadFactory.sellGPToken(token, tokenAmountIn, to, minAssetOut)
  async function handleSell() {
    if (!tokenAmount || !address) return
    setError(null)
    try {
      const amountIn = parseEther(tokenAmount) // GP token has 18 decimals

      // Approve GP token → GradPadFactory
      await writeContractAsync({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [ADDRESSES.GradPadFactory, maxUint256],
      })

      const hash = await writeContractAsync({
        address: ADDRESSES.GradPadFactory,
        abi: ABIS.GradPadFactory,
        functionName: 'sellGPToken',
        args: [tokenAddress, amountIn, address, BigInt(0)],
      })
      setTxHash(hash)
      setTokenAmount('')
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Transaction failed')
    }
  }

  return (
    <div
      className="rounded-2xl p-5 space-y-4"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(255,255,255,0.07)',
      }}
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
            {isPending ? 'Processing...' : `Buy ${tokenSymbol}`}
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
            {isPending ? 'Processing...' : `Sell ${tokenSymbol}`}
          </Button>
        </TabsContent>
      </Tabs>

      {error && <p className="text-xs text-red-400">{error}</p>}
      {txHash && (
        <a
          href={`https://basescan.org/tx/${txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="block text-center text-xs hover:underline"
          style={{ color: '#fbbf24' }}
        >
          View on BaseScan ↗
        </a>
      )}
    </div>
  )
}
