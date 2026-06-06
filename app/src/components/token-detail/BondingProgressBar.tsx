interface Props {
  bondingPhase: boolean
  totalVolume: string
  graduationThreshold?: string
}

export function BondingProgressBar({ bondingPhase, totalVolume, graduationThreshold = '100000' }: Props) {
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
  const threshold = parseFloat(graduationThreshold)
  const pct = threshold > 0 ? Math.min((raised / threshold) * 100, 100) : 0

  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs" style={{ color: '#6b7280' }}>
        <span>Bonding progress</span>
        <span>{pct.toFixed(1)}% to graduation</span>
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
