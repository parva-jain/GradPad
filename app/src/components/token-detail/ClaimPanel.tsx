'use client'

import { useAccount, useWriteContract } from 'wagmi'
import { ABIS } from '@/lib/contracts'
import { Bucket } from '@/types'
import { Button } from '@/components/ui/button'
import { basisPointsToPercent } from '@/lib/utils'

interface Props {
  tokenAddress: `0x${string}`
  buckets: Bucket[]
  graduatedAt: string | null
}

export function ClaimPanel({ tokenAddress, buckets, graduatedAt }: Props) {
  const { address } = useAccount()
  const { writeContractAsync, isPending } = useWriteContract()

  // Only show for graduated tokens with claimable buckets for connected wallet
  if (!address || !graduatedAt) return null

  const claimableBuckets = buckets.filter(
    b => !b.isLiquidity && b.recipient.toLowerCase() === address.toLowerCase()
  )

  if (claimableBuckets.length === 0) return null

  async function handleClaim(bucketIndex: number) {
    try {
      await writeContractAsync({
        address: tokenAddress,
        abi: ABIS.GradPadToken,
        functionName: 'claimBucket',
        args: [BigInt(bucketIndex)],
      })
    } catch (err) {
      console.error('Claim failed:', err)
    }
  }

  return (
    <div
      className="rounded-2xl p-5 space-y-3"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(16,185,129,0.15)',
      }}
    >
      <h2 className="text-sm font-semibold text-white">Your Vesting Positions</h2>
      {claimableBuckets.map(bucket => (
        <div key={bucket.id} className="flex items-center justify-between py-1">
          <div>
            <p className="text-sm font-medium text-white">{bucket.name}</p>
            <p className="text-xs text-muted-foreground">{basisPointsToPercent(bucket.basisPoints)} allocation</p>
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={() => handleClaim(bucket.index)}
            disabled={isPending}
            style={{ border: '1px solid rgba(16,185,129,0.3)', color: '#34d399' }}
          >
            Claim
          </Button>
        </div>
      ))}
    </div>
  )
}
