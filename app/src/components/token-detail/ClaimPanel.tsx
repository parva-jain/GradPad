'use client'

import { useState } from 'react'
import { useAccount, useWriteContract, useReadContracts } from 'wagmi'
import { formatUnits } from 'viem'
import { ABIS } from '@/lib/contracts'
import { Bucket } from '@/types'
import { Button } from '@/components/ui/button'
import { basisPointsToPercent } from '@/lib/utils'

const CLAIMED_ABI = [
  {
    name: 'claimedPerBucket',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'index', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
] as const

interface Props {
  tokenAddress: `0x${string}`
  tokenSymbol: string
  buckets: Bucket[]
  graduatedAt: string | null
  totalSupply: number
}

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

function fmtTokens(n: number, symbol: string): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M ${symbol}`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K ${symbol}`
  return `${n.toFixed(2)} ${symbol}`
}

function StatBox({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div
      className="rounded-lg p-2.5 text-center"
      style={{ background: 'rgba(255,255,255,0.04)' }}
    >
      <p className="text-xs mb-0.5" style={{ color: '#6b7280' }}>{label}</p>
      <p
        className="text-xs font-bold tabular-nums"
        style={{ color: highlight ? '#34d399' : '#e5e7eb' }}
      >
        {value}
      </p>
    </div>
  )
}

export function ClaimPanel({ tokenAddress, tokenSymbol, buckets, graduatedAt, totalSupply }: Props) {
  const { address } = useAccount()
  const { writeContractAsync, isPending } = useWriteContract()
  const [claimingIndex, setClaimingIndex] = useState<number | null>(null)
  const [errors, setErrors] = useState<Record<number, string>>({})

  const vestingBuckets = buckets.filter(b => !b.isLiquidity)
  const gradTimestamp = graduatedAt ? parseInt(graduatedAt) : 0

  const { data: claimedData, refetch } = useReadContracts({
    contracts: vestingBuckets.map(b => ({
      address: tokenAddress,
      abi: CLAIMED_ABI,
      functionName: 'claimedPerBucket' as const,
      args: [BigInt(b.index)] as const,
    })),
    query: { enabled: vestingBuckets.length > 0 },
  })

  if (!address) return null

  const enriched = vestingBuckets.map((bucket, i) => {
    const totalAllocated = totalSupply * (bucket.basisPoints / 10_000)
    const claimedRaw = claimedData?.[i]?.result
    const claimed = claimedRaw ? Number(formatUnits(claimedRaw as bigint, 18)) : 0
    const unlocked = gradTimestamp ? computeUnlocked(bucket, gradTimestamp, totalAllocated) : 0
    const claimable = Math.max(0, unlocked - claimed)
    const isOwner = bucket.recipient.toLowerCase() === address.toLowerCase()
    return { bucket, totalAllocated, claimed, unlocked, claimable, isOwner }
  })

  const myBuckets = enriched.filter(b => b.isOwner)
  if (myBuckets.length === 0) return null

  async function handleClaim(bucket: Bucket) {
    setClaimingIndex(bucket.index)
    setErrors(prev => { const e = { ...prev }; delete e[bucket.index]; return e })
    try {
      await writeContractAsync({
        address: tokenAddress,
        abi: ABIS.GradPadToken,
        functionName: 'claimBucket',
        args: [BigInt(bucket.index)],
      })
      await refetch()
    } catch (err: unknown) {
      setErrors(prev => ({
        ...prev,
        [bucket.index]: err instanceof Error ? err.message.slice(0, 100) : 'Claim failed',
      }))
    } finally {
      setClaimingIndex(null)
    }
  }

  return (
    <div
      className="rounded-2xl p-5 space-y-5"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(16,185,129,0.2)',
      }}
    >
      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-bold text-white">Your Vesting</h2>
        <span
          className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded"
          style={{
            background: 'rgba(16,185,129,0.12)',
            border: '1px solid rgba(16,185,129,0.2)',
            color: '#34d399',
          }}
        >
          {myBuckets.length} stream{myBuckets.length !== 1 ? 's' : ''}
        </span>
      </div>

      {myBuckets.map(({ bucket, totalAllocated, claimed, unlocked, claimable }) => {
        const unlockPct = totalAllocated > 0 ? Math.min((unlocked / totalAllocated) * 100, 100) : 0
        const isClaiming = claimingIndex === bucket.index && isPending
        const cliffEnd = gradTimestamp ? new Date((gradTimestamp + bucket.cliff) * 1000) : null
        const vestingEnd =
          gradTimestamp && bucket.vestingDuration > 0
            ? new Date((gradTimestamp + bucket.cliff + bucket.vestingDuration) * 1000)
            : null
        const now = Date.now()
        const inCliff = cliffEnd && now < cliffEnd.getTime()
        const fullyVested = unlocked >= totalAllocated - 0.001

        return (
          <div
            key={bucket.id}
            className="space-y-3 pb-5"
            style={{ borderBottom: '1px solid rgba(255,255,255,0.06)' }}
          >
            {/* Stream header */}
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-bold text-white">{bucket.name}</p>
                <p className="text-xs" style={{ color: '#6b7280' }}>
                  {basisPointsToPercent(bucket.basisPoints)} of supply
                </p>
              </div>
              {fullyVested ? (
                <span
                  className="text-xs font-bold px-2 py-0.5 rounded"
                  style={{
                    background: 'rgba(16,185,129,0.12)',
                    color: '#34d399',
                    border: '1px solid rgba(16,185,129,0.2)',
                  }}
                >
                  Fully Vested
                </span>
              ) : inCliff ? (
                <span
                  className="text-xs font-bold px-2 py-0.5 rounded"
                  style={{
                    background: 'rgba(251,191,36,0.12)',
                    color: '#fbbf24',
                    border: '1px solid rgba(251,191,36,0.2)',
                  }}
                >
                  In Cliff
                </span>
              ) : !graduatedAt ? (
                <span
                  className="text-xs font-bold px-2 py-0.5 rounded"
                  style={{
                    background: 'rgba(255,255,255,0.06)',
                    color: '#9ca3af',
                    border: '1px solid rgba(255,255,255,0.1)',
                  }}
                >
                  Pending
                </span>
              ) : (
                <span
                  className="text-xs font-bold px-2 py-0.5 rounded"
                  style={{
                    background: 'rgba(16,185,129,0.08)',
                    color: '#34d399',
                    border: '1px solid rgba(16,185,129,0.15)',
                  }}
                >
                  Streaming
                </span>
              )}
            </div>

            {/* Progress bar */}
            <div className="space-y-1">
              <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
                <span>Unlocked</span>
                <span style={{ color: unlockPct > 0 ? '#34d399' : '#6b7280' }}>
                  {unlockPct.toFixed(1)}%
                </span>
              </div>
              <div
                className="relative h-3 rounded-full overflow-hidden"
                style={{ background: 'rgba(255,255,255,0.06)' }}
              >
                {/* Claimed portion */}
                <div
                  className="absolute left-0 top-0 h-full rounded-full"
                  style={{
                    width: `${totalAllocated > 0 ? Math.min((claimed / totalAllocated) * 100, 100) : 0}%`,
                    background: 'rgba(16,185,129,0.3)',
                  }}
                />
                {/* Unlocked portion (overlaid with gradient) */}
                <div
                  className="absolute left-0 top-0 h-full rounded-full transition-all duration-500"
                  style={{
                    width: `${unlockPct}%`,
                    background: 'linear-gradient(90deg, #059669, #34d399)',
                    opacity: 0.85,
                  }}
                />
              </div>
              <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
                <span style={{ color: '#34d399' }}>{fmtTokens(unlocked, tokenSymbol)} unlocked</span>
                <span>{fmtTokens(claimed, tokenSymbol)} claimed</span>
              </div>
            </div>

            {/* Stats grid */}
            <div className="grid grid-cols-3 gap-1.5">
              <StatBox label="Total" value={fmtTokens(totalAllocated, tokenSymbol)} />
              <StatBox label="Unlocked" value={fmtTokens(unlocked, tokenSymbol)} highlight />
              <StatBox
                label="Claimable"
                value={fmtTokens(claimable, tokenSymbol)}
                highlight={claimable > 0.001}
              />
            </div>

            {/* Schedule */}
            {!graduatedAt ? (
              <p className="text-xs" style={{ color: '#f59e0b' }}>
                Vesting starts upon token graduation
              </p>
            ) : (
              <div className="text-xs space-y-0.5" style={{ color: '#6b7280' }}>
                {bucket.cliff > 0 && cliffEnd && (
                  <div className="flex justify-between">
                    <span>Cliff ends</span>
                    <span style={{ color: inCliff ? '#fbbf24' : '#9ca3af' }}>
                      {cliffEnd.toLocaleDateString()}
                    </span>
                  </div>
                )}
                {vestingEnd && (
                  <div className="flex justify-between">
                    <span>Fully vested</span>
                    <span style={{ color: '#9ca3af' }}>{vestingEnd.toLocaleDateString()}</span>
                  </div>
                )}
                {!cliffEnd && bucket.vestingDuration === 0 && (
                  <p style={{ color: '#34d399' }}>Instant — fully unlocked at graduation</p>
                )}
              </div>
            )}

            {/* Error */}
            {errors[bucket.index] && (
              <p className="text-xs text-red-400 break-words">{errors[bucket.index]}</p>
            )}

            {/* Claim button */}
            {graduatedAt && claimable > 0.001 ? (
              <Button
                className="w-full font-bold"
                onClick={() => handleClaim(bucket)}
                disabled={isClaiming}
                style={{
                  background: isClaiming
                    ? 'rgba(255,255,255,0.06)'
                    : 'linear-gradient(90deg, #059669, #34d399)',
                  color: isClaiming ? '#6b7280' : '#0c0a06',
                  border: 'none',
                }}
              >
                {isClaiming
                  ? 'Claiming...'
                  : `Claim ${fmtTokens(claimable, tokenSymbol)}`}
              </Button>
            ) : graduatedAt && claimable <= 0.001 && claimed > 0 ? (
              <div
                className="text-center text-xs py-2 rounded-lg"
                style={{ background: 'rgba(16,185,129,0.06)', color: '#6b7280' }}
              >
                All unlocked tokens have been claimed
              </div>
            ) : null}
          </div>
        )
      })}
    </div>
  )
}
