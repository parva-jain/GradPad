'use client'

import { useReadContract } from 'wagmi'
import { ADDRESSES, ABIS } from '@/lib/contracts'

interface Props {
  bondingPhase: boolean
  totalVolume: string
  tokenAddress: string
}

export function BondingProgressBar({ bondingPhase, totalVolume, tokenAddress }: Props) {
  const { data: thresholdRaw } = useReadContract({
    address: ADDRESSES.GradPadFactory,
    abi: ABIS.GradPadFactory,
    functionName: 'graduationThreshold',
    args: [tokenAddress as `0x${string}`],
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

  const raised = parseFloat(totalVolume)
  // thresholdRaw is in 6-decimal USDC units; totalVolume is already a decimal string
  const threshold = thresholdRaw ? Number(thresholdRaw) / 1e6 : 0
  const pct = threshold > 0 ? Math.min((raised / threshold) * 100, 100) : 0

  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
        <span>Bonding progress</span>
        <span>
          {threshold > 0
            ? `${pct.toFixed(1)}% · $${raised.toFixed(0)} / $${threshold.toLocaleString()} target`
            : `$${raised.toFixed(0)} raised`}
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
