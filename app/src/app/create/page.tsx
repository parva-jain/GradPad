'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAccount, useWriteContract } from 'wagmi'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { parseUnits, keccak256, encodePacked } from 'viem'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { BucketFormInput } from '@/types'
import { TokenomicsBuilder } from '@/components/create/TokenomicsBuilder'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

const DEFAULT_BUCKETS: BucketFormInput[] = [
  { name: 'Liquidity', basisPoints: 10000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: true },
]

export default function CreatePage() {
  const router = useRouter()
  const { address, isConnected } = useAccount()
  const [name, setName] = useState('')
  const [symbol, setSymbol] = useState('')
  const [buckets, setBuckets] = useState<BucketFormInput[]>(DEFAULT_BUCKETS)

  const { writeContractAsync, isPending } = useWriteContract()

  const total = buckets.reduce((sum, b) => sum + b.basisPoints, 0)
  const hasLiquidity = buckets.filter(b => b.isLiquidity).length === 1
  const canSubmit = name.trim() !== '' && symbol.trim() !== '' && total === 10000 && hasLiquidity && !isPending

  async function handleCreate() {
    if (!address || !canSubmit) return

    const bucketArgs = buckets.map(b => ({
      name: b.name,
      basisPoints: BigInt(b.basisPoints),
      recipient: (b.isLiquidity
        ? '0x0000000000000000000000000000000000000000'
        : b.recipient) as `0x${string}`,
      cliff: BigInt(b.cliff),
      vestingDuration: BigInt(b.vestingDuration),
      isLiquidity: b.isLiquidity,
    }))

    // Generate a deterministic salt from creator address + token name + timestamp
    const salt = keccak256(
      encodePacked(
        ['address', 'string', 'uint256'],
        [address, name, BigInt(Date.now())]
      )
    )

    try {
      await writeContractAsync({
        address: ADDRESSES.GradPadFactory,
        abi: ABIS.GradPadFactory,
        functionName: 'createGPToken',
        args: [
          name,
          symbol.toUpperCase(),
          parseUnits('1000000000', 18),  // 1B supply at 18 decimals
          bucketArgs,
          parseUnits('100000', 6),       // 100k USDC graduation threshold (6 decimals)
          parseUnits('30000', 6),        // 30k USDC virtual reserve (6 decimals)
          salt,
        ],
      })
      router.push('/')
    } catch (err) {
      console.error('Create failed:', err)
    }
  }

  return (
    <main className="max-w-2xl mx-auto px-4 py-8" style={{ minHeight: '100vh' }}>
      <div
        className="rounded-2xl p-6 space-y-6"
        style={{
          background: 'rgba(255,255,255,0.025)',
          border: '1px solid rgba(255,255,255,0.07)',
        }}
      >
        <h1 className="text-2xl font-extrabold text-white tracking-tight">Launch a Token</h1>

        {!isConnected ? (
          <ConnectButton />
        ) : (
          <div className="space-y-6">
            {/* Name + Symbol */}
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Token Name</Label>
                <Input
                  value={name}
                  onChange={e => setName(e.target.value)}
                  placeholder="My Token"
                  style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
                />
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Symbol</Label>
                <Input
                  value={symbol}
                  onChange={e => setSymbol(e.target.value.toUpperCase())}
                  placeholder="MTK"
                  style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
                />
              </div>
            </div>

            {/* Tokenomics builder */}
            <div className="space-y-2">
              <Label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Tokenomics</Label>
              <TokenomicsBuilder buckets={buckets} onChange={setBuckets} />
            </div>

            {/* Submit */}
            <Button
              className="w-full font-bold text-base py-5"
              onClick={handleCreate}
              disabled={!canSubmit}
              style={{
                background: !canSubmit
                  ? 'rgba(255,255,255,0.06)'
                  : 'linear-gradient(90deg, #d97706, #fbbf24)',
                color: !canSubmit ? '#6b7280' : '#0c0a06',
                border: 'none',
              }}
            >
              {isPending ? 'Launching...' : 'Launch Token'}
            </Button>
          </div>
        )}
      </div>
    </main>
  )
}
