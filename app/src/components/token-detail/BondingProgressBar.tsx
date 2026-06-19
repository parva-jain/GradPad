'use client'

import { useReadContract } from 'wagmi'
import { ADDRESSES, ABIS } from '@/lib/contracts'

const BC_PAIR_ABI = [
  { name: 'assetBalance', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const

interface Props {
  bondingPhase: boolean
  tokenAddress: string
}

export function BondingProgressBar({ bondingPhase, tokenAddress }: Props) {
  const { data: thresholdRaw } = useReadContract({
    address: ADDRESSES.GradPadFactory,
    abi: ABIS.GradPadFactory,
    functionName: 'graduationThreshold',
    args: [tokenAddress as `0x${string}`],
  })

  const { data: pairAddress } = useReadContract({
    address: ADDRESSES.GradPadFactory,
    abi: ABIS.GradPadFactory,
    functionName: 'tokenToPair',
    args: [tokenAddress as `0x${string}`],
    query: { enabled: bondingPhase },
  })

  const { data: assetBalanceRaw } = useReadContract({
    address: pairAddress as `0x${string}` | undefined,
    abi: BC_PAIR_ABI,
    functionName: 'assetBalance',
    query: { enabled: bondingPhase && !!pairAddress },
  })

  if (!bondingPhase) {
    return (
      <div className="space-y-1">
        <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
          <span>Bonding progress</span>
          <span style={{ color: '#34d399' }}>Graduated ✓</span>
        </div>
        <div className="h-1.5 w-full rounded-full" style={{ background: 'rgba(255,255,255,0.06)' }}>
          <div
            className="h-full w-full rounded-full"
            style={{
              background: 'linear-gradient(90deg, #059669, #34d399)',
              boxShadow: '0 0 10px rgba(16,185,129,0.4)',
            }}
          />
        </div>
      </div>
    )
  }

  // Use real net USDC in BCPair (assetBalance), not totalVolume which is inflated by sells
  const threshold = thresholdRaw ? Number(thresholdRaw) / 1e6 : 0
  const netUsdc   = assetBalanceRaw !== undefined ? Number(assetBalanceRaw) / 1e6 : null
  const pct       = threshold > 0 && netUsdc !== null ? Math.min((netUsdc / threshold) * 100, 100) : 0

  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
        <span>Bonding progress</span>
        <span>
          {threshold > 0 && netUsdc !== null
            ? `${pct.toFixed(1)}% · $${netUsdc.toFixed(0)} / $${threshold.toLocaleString()} target`
            : threshold > 0
              ? 'Loading...'
              : ''}
        </span>
      </div>
      <div className="h-1.5 w-full rounded-full" style={{ background: 'rgba(255,255,255,0.06)' }}>
        <div
          className="h-full rounded-full transition-all duration-500"
          style={{
            width: `${pct}%`,
            background: 'linear-gradient(90deg, #d97706, #fbbf24)',
            boxShadow: '0 0 10px rgba(251,191,36,0.4)',
          }}
        />
      </div>
    </div>
  )
}
