import { Bucket } from '@/types'
import { secondsToDuration, basisPointsToPercent } from '@/lib/utils'

interface Props {
  bucket: Bucket
  graduatedAt: string | null
}

export function VestingTimeline({ bucket, graduatedAt }: Props) {
  const now = Date.now() / 1000
  const gradTime = graduatedAt ? parseInt(graduatedAt) : null

  let cliffPct = 0
  let vestedPct = 0

  if (gradTime) {
    const totalDuration = bucket.cliff + bucket.vestingDuration
    if (totalDuration > 0) {
      cliffPct = Math.min((bucket.cliff / totalDuration) * 100, 100)
      const elapsed = Math.max(0, now - gradTime - bucket.cliff)
      const vestFraction =
        bucket.vestingDuration > 0
          ? Math.min(elapsed / bucket.vestingDuration, 1)
          : now > gradTime + bucket.cliff
          ? 1
          : 0
      vestedPct = (1 - cliffPct / 100) * vestFraction * 100
    }
  }

  return (
    <div className="space-y-1.5">
      <div className="flex justify-between text-xs">
        <span className="font-medium text-white">{bucket.name}</span>
        <span style={{ color: '#6b7280' }}>{basisPointsToPercent(bucket.basisPoints)}</span>
      </div>
      <div
        className="flex h-1.5 w-full overflow-hidden rounded-full"
        style={{ background: 'rgba(255,255,255,0.06)' }}
      >
        <div style={{ width: `${cliffPct}%`, background: 'rgba(255,255,255,0.15)' }} />
        <div
          style={{
            width: `${vestedPct}%`,
            background: 'linear-gradient(90deg, #d97706, #fbbf24)',
          }}
        />
      </div>
      <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
        <span>Cliff: {secondsToDuration(bucket.cliff)}</span>
        <span>Vest: {secondsToDuration(bucket.vestingDuration)}</span>
      </div>
    </div>
  )
}
