'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
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
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()
  const [countdown, setCountdown] = useState(5)

  const { writeContractAsync, isPending } = useWriteContract()

  const { data: receipt } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: !!txHash },
  })

  const launched = !!receipt

  useEffect(() => {
    if (!launched) return
    if (countdown === 0) {
      router.push('/')
      return
    }
    const t = setTimeout(() => setCountdown(c => c - 1), 1000)
    return () => clearTimeout(t)
  }, [launched, countdown, router])

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

    const salt = keccak256(
      encodePacked(
        ['address', 'string', 'uint256'],
        [address, name, BigInt(Date.now())]
      )
    )

    try {
      const hash = await writeContractAsync({
        address: ADDRESSES.GradPadFactory,
        abi: ABIS.GradPadFactory,
        functionName: 'createGPToken',
        args: [
          name,
          symbol.toUpperCase(),
          parseUnits('1000000000', 18),
          bucketArgs,
          parseUnits('100000', 6),
          parseUnits('30000', 6),
          salt,
        ],
      })
      setTxHash(hash)
    } catch (err) {
      console.error('Create failed:', err)
    }
  }

  // Confirming on-chain state
  if (txHash && !launched) {
    return (
      <main className="flex items-center justify-center min-h-screen px-4" style={{ background: '#0c0a06' }}>
        <div
          className="w-full max-w-sm rounded-2xl p-8 space-y-4 text-center"
          style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
        >
          <div
            className="mx-auto h-10 w-10 rounded-full animate-spin"
            style={{ border: '3px solid rgba(251,191,36,0.15)', borderTopColor: '#fbbf24' }}
          />
          <h2 className="text-lg font-bold text-white">Confirming on-chain...</h2>
          <p className="text-sm text-muted-foreground">
            Waiting for your transaction to be included in a block. This usually takes a few seconds on Base.
          </p>
          <a
            href={`https://basescan.org/tx/${txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="block text-xs hover:underline"
            style={{ color: '#fbbf24' }}
          >
            View on BaseScan ↗
          </a>
        </div>
      </main>
    )
  }

  // Launched state
  if (launched) {
    return (
      <main className="flex items-center justify-center min-h-screen px-4" style={{ background: '#0c0a06' }}>
        <div
          className="w-full max-w-sm rounded-2xl p-8 space-y-4 text-center"
          style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(16,185,129,0.2)' }}
        >
          <div
            className="mx-auto h-10 w-10 rounded-full flex items-center justify-center"
            style={{ background: 'rgba(16,185,129,0.12)', border: '1px solid rgba(16,185,129,0.3)' }}
          >
            <div className="h-5 w-5 rounded-full" style={{ background: '#34d399' }} />
          </div>
          <h2 className="text-lg font-bold text-white">Token Launched!</h2>
          <p className="text-sm text-muted-foreground">
            Your token is live on Base. It will appear on Discover once the subgraph indexes it — usually within 30–60 seconds.
          </p>
          <Button
            className="w-full font-bold"
            onClick={() => router.push('/')}
            style={{ background: 'linear-gradient(90deg, #d97706, #fbbf24)', color: '#0c0a06', border: 'none' }}
          >
            Go to Discover
          </Button>
          <p className="text-xs text-muted-foreground">
            Redirecting automatically in {countdown}s...
          </p>
        </div>
      </main>
    )
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
              {isPending ? 'Confirm in wallet...' : 'Launch Token'}
            </Button>
          </div>
        )}
      </div>
    </main>
  )
}
