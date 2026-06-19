'use client'

import { useState } from 'react'
import { useReadContracts } from 'wagmi'
import { formatUnits } from 'viem'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { Bucket } from '@/types'
import { basisPointsToPercent, shortenAddress, secondsToDuration } from '@/lib/utils'

const PIE_COLORS = ['#fbbf24', '#10b981', '#8b5cf6', '#3b82f6', '#ec4899', '#f97316', '#14b8a6', '#ef4444']

const CLAIMED_ABI = [
  {
    name: 'claimedPerBucket',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
] as const

function computeUnlocked(
  bucket: Bucket,
  gradTimestamp: number,
  totalAllocated: number,
): number {
  if (!gradTimestamp) return 0
  const now = Math.floor(Date.now() / 1000)
  const cliffEnd = gradTimestamp + bucket.cliff
  if (now < cliffEnd) return 0
  if (bucket.vestingDuration === 0) return totalAllocated
  const vestingEnd = cliffEnd + bucket.vestingDuration
  if (now >= vestingEnd) return totalAllocated
  return (totalAllocated * (now - cliffEnd)) / bucket.vestingDuration
}

function fmtTokens(n: number): string {
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(2)}B`
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return n.toLocaleString(undefined, { maximumFractionDigits: 0 })
}

function CopyBtn({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <button
      onClick={() => { navigator.clipboard.writeText(text); setCopied(true); setTimeout(() => setCopied(false), 1500) }}
      className="text-xs px-1 py-0.5 rounded shrink-0"
      style={{
        background: copied ? 'rgba(16,185,129,0.12)' : 'rgba(255,255,255,0.05)',
        color: copied ? '#34d399' : '#6b7280',
        border: copied ? '1px solid rgba(16,185,129,0.2)' : '1px solid rgba(255,255,255,0.08)',
      }}
    >
      {copied ? '✓' : 'copy'}
    </button>
  )
}

interface Props {
  tokenAddress: `0x${string}`
  buckets: Bucket[]
  bondingPhase: boolean
  graduatedAt: string | null
  totalSupply: number
}

export function AllocationPanel({ tokenAddress, buckets, bondingPhase, graduatedAt, totalSupply }: Props) {
  const gradTimestamp = graduatedAt ? parseInt(graduatedAt) : 0

  const { data: claimedData } = useReadContracts({
    contracts: buckets.map(b => ({
      address: tokenAddress,
      abi: CLAIMED_ABI,
      functionName: 'claimedPerBucket' as const,
      args: [BigInt(b.index)] as const,
    })),
    query: { enabled: !bondingPhase && buckets.length > 0 },
  })

  const enriched = buckets.map((bucket, i) => {
    const totalAllocated = totalSupply * (bucket.basisPoints / 10_000)
    const claimedRaw = claimedData?.[i]?.result
    const claimed = claimedRaw ? Number(formatUnits(claimedRaw as bigint, 18)) : 0
    const unlocked = bondingPhase ? 0 : computeUnlocked(bucket, gradTimestamp, totalAllocated)
    const unlockPct = totalAllocated > 0 ? Math.min((unlocked / totalAllocated) * 100, 100) : 0
    return { bucket, totalAllocated, claimed, unlocked, unlockPct }
  })

  const pieData = buckets.map(b => ({ name: b.name, value: b.basisPoints / 100 }))

  return (
    <div
      className="rounded-2xl p-5 space-y-4"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(255,255,255,0.07)',
      }}
    >
      <h2 className="text-base font-bold text-white">Token Allocation</h2>

      {/* Pie chart */}
      <div className="h-44 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={pieData}
              cx="50%"
              cy="50%"
              innerRadius={48}
              outerRadius={74}
              paddingAngle={2}
              dataKey="value"
              strokeWidth={0}
            >
              {buckets.map((_, i) => (
                <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
              ))}
            </Pie>
            <Tooltip
              contentStyle={{
                background: '#18181b',
                border: '1px solid rgba(251,191,36,0.2)',
                borderRadius: '8px',
                color: '#fff',
                fontSize: 12,
              }}
              // @ts-expect-error recharts types
              formatter={(value: number, name: string) => [`${name}: ${value}%`, '']}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>

      {/* Bucket rows */}
      <div className="space-y-2">
        {enriched.map(({ bucket, totalAllocated, claimed, unlocked, unlockPct }, i) => {
          const color = PIE_COLORS[i % PIE_COLORS.length]
          return (
            <div
              key={bucket.id}
              className="rounded-xl p-3 space-y-2"
              style={{
                background: 'rgba(255,255,255,0.03)',
                border: '1px solid rgba(255,255,255,0.05)',
              }}
            >
              {/* Name + % */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 min-w-0">
                  <div
                    style={{ width: 8, height: 8, borderRadius: 2, background: color, flexShrink: 0 }}
                  />
                  <span className="text-sm font-semibold text-white truncate">{bucket.name}</span>
                </div>
                <span className="text-xs font-bold shrink-0 ml-2" style={{ color }}>
                  {basisPointsToPercent(bucket.basisPoints)}
                </span>
              </div>

              {/* Token count */}
              <p className="text-xs tabular-nums" style={{ color: '#9ca3af' }}>
                {fmtTokens(totalAllocated)} tokens
              </p>

              {bucket.isLiquidity ? (
                <p className="text-xs" style={{ color: '#6b7280' }}>
                  Protocol-owned LP · permanently locked
                </p>
              ) : (
                <>
                  {/* Recipient */}
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <span className="text-xs" style={{ color: '#6b7280' }}>Recipient:</span>
                    <span className="text-xs font-mono" style={{ color: '#e5e7eb' }}>
                      {shortenAddress(bucket.recipient)}
                    </span>
                    <CopyBtn text={bucket.recipient} />
                  </div>

                  {/* Schedule */}
                  {bondingPhase ? (
                    <p className="text-xs" style={{ color: '#f59e0b' }}>
                      Allocates upon graduation
                    </p>
                  ) : (
                    <div className="space-y-1.5">
                      <div className="flex gap-3 text-xs flex-wrap" style={{ color: '#6b7280' }}>
                        {bucket.cliff > 0 && (
                          <span>Cliff: {secondsToDuration(bucket.cliff)}</span>
                        )}
                        {bucket.vestingDuration > 0 ? (
                          <span>Vesting: {secondsToDuration(bucket.vestingDuration)}</span>
                        ) : bucket.cliff === 0 ? (
                          <span>Instant at graduation</span>
                        ) : (
                          <span>Instant at cliff end</span>
                        )}
                      </div>

                      {/* Unlock progress */}
                      <div>
                        <div className="flex justify-between text-xs mb-1" style={{ color: '#6b7280' }}>
                          <span>Unlocked</span>
                          <span style={{ color: '#34d399' }}>{unlockPct.toFixed(1)}%</span>
                        </div>
                        <div
                          className="h-1.5 rounded-full overflow-hidden"
                          style={{ background: 'rgba(255,255,255,0.06)' }}
                        >
                          <div
                            className="h-full rounded-full transition-all duration-500"
                            style={{
                              width: `${unlockPct}%`,
                              background: 'linear-gradient(90deg, #059669, #34d399)',
                            }}
                          />
                        </div>
                        <div className="flex justify-between text-xs mt-1" style={{ color: '#6b7280' }}>
                          <span>{fmtTokens(unlocked)} unlocked</span>
                          <span>{fmtTokens(claimed)} claimed</span>
                        </div>
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
