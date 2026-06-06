'use client'

import { useState } from 'react'
import { BucketFormInput } from '@/types'
import { BucketRow } from './BucketRow'
import { Button } from '@/components/ui/button'
import { Plus } from 'lucide-react'

const MEME_PRESET: BucketFormInput[] = [
  { name: 'Liquidity', basisPoints: 10000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: true },
]

const FAIR_LAUNCH_PRESET: BucketFormInput[] = [
  { name: 'Liquidity',  basisPoints: 8000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: true },
  { name: 'Community',  basisPoints: 2000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: false },
]

const VC_BACKED_PRESET: BucketFormInput[] = [
  { name: 'Liquidity', basisPoints: 6000, recipient: '', cliff: 0,           vestingDuration: 0,           isLiquidity: true },
  { name: 'Team',      basisPoints: 2000, recipient: '', cliff: 365 * 86400, vestingDuration: 730 * 86400, isLiquidity: false },
  { name: 'Treasury',  basisPoints: 2000, recipient: '', cliff: 0,           vestingDuration: 0,           isLiquidity: false },
]

interface Props {
  buckets: BucketFormInput[]
  onChange: (buckets: BucketFormInput[]) => void
}

export function TokenomicsBuilder({ buckets, onChange }: Props) {
  const [mode, setMode] = useState<'meme' | 'structured'>('meme')

  function handleModeChange(newMode: 'meme' | 'structured') {
    setMode(newMode)
    if (newMode === 'meme') onChange(MEME_PRESET)
  }

  function handleBucketChange(index: number, updated: Partial<BucketFormInput>) {
    onChange(buckets.map((b, i) => i === index ? { ...b, ...updated } : b))
  }

  function handleAddBucket() {
    if (buckets.length >= 10) return
    onChange([...buckets, { name: 'Team', basisPoints: 0, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: false }])
  }

  function handleRemoveBucket(index: number) {
    onChange(buckets.filter((_, i) => i !== index))
  }

  const total = buckets.reduce((sum, b) => sum + b.basisPoints, 0)
  const isValid = total === 10000 && buckets.filter(b => b.isLiquidity).length === 1

  return (
    <div className="space-y-4">
      {/* Mode toggle */}
      <div
        className="inline-flex items-center p-1 rounded-xl"
        style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.06)' }}
      >
        {(['meme', 'structured'] as const).map(m => (
          <button
            key={m}
            type="button"
            onClick={() => handleModeChange(m)}
            className="px-4 py-1.5 rounded-lg text-sm font-medium capitalize transition-all"
            style={
              mode === m
                ? { background: 'rgba(251,191,36,0.12)', color: '#fbbf24' }
                : { color: '#6b7280' }
            }
          >
            {m}
          </button>
        ))}
      </div>

      {mode === 'structured' && (
        <div className="space-y-3">
          {/* Presets */}
          <div className="flex gap-2 items-center">
            <span className="text-xs text-muted-foreground">Presets:</span>
            {[
              { label: 'Fair Launch', preset: FAIR_LAUNCH_PRESET },
              { label: 'VC-Backed',   preset: VC_BACKED_PRESET },
            ].map(({ label, preset }) => (
              <button
                key={label}
                type="button"
                onClick={() => onChange(preset)}
                className="text-xs px-2 py-1 rounded transition-colors"
                style={{
                  background: 'rgba(255,255,255,0.04)',
                  border: '1px solid rgba(255,255,255,0.08)',
                  color: '#9ca3af',
                }}
              >
                {label}
              </button>
            ))}
          </div>

          {/* Column headers */}
          <div className="grid text-xs text-muted-foreground px-1" style={{ gridTemplateColumns: '3fr 1fr 3fr 2fr 2fr auto' }}>
            <span>Name</span><span>%</span><span>Recipient</span><span>Cliff</span><span>Vesting</span><span />
          </div>

          {/* Bucket rows */}
          {buckets.map((b, i) => (
            <BucketRow
              key={i}
              bucket={b}
              index={i}
              onChange={handleBucketChange}
              onRemove={handleRemoveBucket}
              canRemove={!b.isLiquidity && buckets.length > 1}
            />
          ))}

          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleAddBucket}
            disabled={buckets.length >= 10}
            style={{ border: '1px solid rgba(255,255,255,0.15)', color: '#9ca3af' }}
          >
            <Plus className="h-4 w-4 mr-1" /> Add Bucket
          </Button>
        </div>
      )}

      {/* Allocation bar */}
      <div className="space-y-1">
        <div className="flex h-3 w-full overflow-hidden rounded-full" style={{ background: 'rgba(255,255,255,0.06)' }}>
          {buckets.map((b, i) => (
            <div
              key={i}
              className="h-full transition-all"
              style={{
                width: `${b.basisPoints / 100}%`,
                background: b.isLiquidity ? '#fbbf24' : '#f59e0b',
              }}
            />
          ))}
        </div>
        <div className="text-xs text-right font-medium" style={{ color: isValid ? '#34d399' : '#f87171' }}>
          {(total / 100).toFixed(1)}% / 100%{isValid ? ' ✓' : ''}
        </div>
      </div>
    </div>
  )
}
