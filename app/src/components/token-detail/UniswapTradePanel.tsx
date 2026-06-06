'use client'

import { useState } from 'react'
import { useAccount, useWriteContract } from 'wagmi'
import { parseUnits, parseEther } from 'viem'
import { ADDRESSES } from '@/lib/contracts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'

const UNISWAP_V2_ROUTER = '0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24' as const

const UNISWAP_V2_ROUTER_ABI = [
  {
    name: 'swapExactTokensForTokens',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'amountIn', type: 'uint256' },
      { name: 'amountOutMin', type: 'uint256' },
      { name: 'path', type: 'address[]' },
      { name: 'to', type: 'address' },
      { name: 'deadline', type: 'uint256' },
    ],
    outputs: [{ name: 'amounts', type: 'uint256[]' }],
  },
] as const

// Minimal ERC-20 approve
const ERC20_APPROVE_ABI = [
  { name: 'approve', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const

interface Props {
  tokenAddress: `0x${string}`
  tokenSymbol: string
  uniswapPair: string
}

export function UniswapTradePanel({ tokenAddress, tokenSymbol }: Props) {
  const { address } = useAccount()
  const [amount, setAmount] = useState('')
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined)
  const [error, setError] = useState<string | null>(null)
  const { writeContractAsync, isPending } = useWriteContract()

  const deadline = BigInt(Math.floor(Date.now() / 1000) + 1200)

  async function handleBuy() {
    if (!amount || !address) return
    setError(null)
    try {
      // Approve USDC → Uniswap router
      await writeContractAsync({
        address: ADDRESSES.MockUSDC,
        abi: ERC20_APPROVE_ABI,
        functionName: 'approve',
        args: [UNISWAP_V2_ROUTER, parseUnits(amount, 6)],
      })
      const hash = await writeContractAsync({
        address: UNISWAP_V2_ROUTER,
        abi: UNISWAP_V2_ROUTER_ABI,
        functionName: 'swapExactTokensForTokens',
        args: [parseUnits(amount, 6), BigInt(0), [ADDRESSES.MockUSDC, tokenAddress], address, deadline],
      })
      setTxHash(hash)
      setAmount('')
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Swap failed')
    }
  }

  async function handleSell() {
    if (!amount || !address) return
    setError(null)
    try {
      // Approve GP token → Uniswap router
      await writeContractAsync({
        address: tokenAddress,
        abi: ERC20_APPROVE_ABI,
        functionName: 'approve',
        args: [UNISWAP_V2_ROUTER, parseEther(amount)],
      })
      const hash = await writeContractAsync({
        address: UNISWAP_V2_ROUTER,
        abi: UNISWAP_V2_ROUTER_ABI,
        functionName: 'swapExactTokensForTokens',
        args: [parseEther(amount), BigInt(0), [tokenAddress, ADDRESSES.MockUSDC], address, deadline],
      })
      setTxHash(hash)
      setAmount('')
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Swap failed')
    }
  }

  return (
    <div
      className="rounded-2xl p-5 space-y-4"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(16,185,129,0.15)',
      }}
    >
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-white">Trade</h2>
        <span
          className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded"
          style={{ background: 'rgba(16,185,129,0.12)', border: '1px solid rgba(16,185,129,0.2)', color: '#34d399' }}
        >
          Graduated
        </span>
      </div>

      <Tabs defaultValue="buy">
        <TabsList className="w-full" style={{ background: 'rgba(255,255,255,0.05)' }}>
          <TabsTrigger value="buy" className="flex-1">Buy</TabsTrigger>
          <TabsTrigger value="sell" className="flex-1">Sell</TabsTrigger>
        </TabsList>
        <TabsContent value="buy" className="space-y-3 pt-3">
          <div className="text-xs text-muted-foreground">You pay (mUSDC)</div>
          <Input
            type="number"
            value={amount}
            onChange={e => setAmount(e.target.value)}
            placeholder="0.0"
            style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
          />
          <Button
            className="w-full font-bold"
            onClick={handleBuy}
            disabled={!amount || isPending || !address}
            style={{
              background: !amount || isPending || !address
                ? 'rgba(255,255,255,0.06)'
                : 'linear-gradient(90deg, #059669, #34d399)',
              color: !amount || isPending || !address ? '#6b7280' : '#0c0a06',
              border: 'none',
            }}
          >
            {isPending ? 'Swapping...' : `Buy ${tokenSymbol}`}
          </Button>
        </TabsContent>
        <TabsContent value="sell" className="space-y-3 pt-3">
          <div className="text-xs text-muted-foreground">You sell ({tokenSymbol})</div>
          <Input
            type="number"
            value={amount}
            onChange={e => setAmount(e.target.value)}
            placeholder="0.0"
            style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
          />
          <Button
            className="w-full font-bold"
            onClick={handleSell}
            disabled={!amount || isPending || !address}
            style={{
              background: !amount || isPending || !address
                ? 'rgba(255,255,255,0.06)'
                : '#ef4444',
              color: !amount || isPending || !address ? '#6b7280' : 'white',
              border: 'none',
            }}
          >
            {isPending ? 'Swapping...' : `Sell ${tokenSymbol}`}
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
          style={{ color: '#34d399' }}
        >
          View on BaseScan ↗
        </a>
      )}
    </div>
  )
}
