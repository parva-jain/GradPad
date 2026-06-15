'use client'

import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { Bucket } from '@/types'
import { basisPointsToPercent, secondsToDuration } from '@/lib/utils'

const PIE_COLORS = ['#fbbf24', '#10b981', '#8b5cf6', '#3b82f6', '#ec4899', '#f97316', '#14b8a6', '#ef4444']

interface Props {
  buckets: Bucket[]
}

export function TokenomicsPieChart({ buckets }: Props) {
  const data = buckets.map(b => ({
    name: b.name,
    value: b.basisPoints / 100,
  }))

  return (
    <div className="space-y-4">
      {/* Donut chart */}
      <div className="h-48 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              cx="50%"
              cy="50%"
              innerRadius={52}
              outerRadius={80}
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
              // @ts-expect-error — recharts v3 ValueType is wider than number
              formatter={(value: number) => [`${value}%`, '']}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>

      {/* Bucket info rows */}
      <div className="space-y-2">
        {buckets.map((bucket, i) => (
          <div
            key={bucket.id}
            className="flex items-start gap-3 rounded-xl p-3"
            style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.05)' }}
          >
            <div
              style={{
                width: 10,
                height: 10,
                borderRadius: 3,
                background: PIE_COLORS[i % PIE_COLORS.length],
                flexShrink: 0,
                marginTop: 3,
              }}
            />
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-semibold text-white">{bucket.name}</span>
                <span className="text-xs font-bold tabular-nums" style={{ color: PIE_COLORS[i % PIE_COLORS.length] }}>
                  {basisPointsToPercent(bucket.basisPoints)}
                </span>
              </div>

              {bucket.isLiquidity ? (
                <p className="text-xs mt-0.5" style={{ color: '#6b7280' }}>Protocol-owned LP</p>
              ) : (
                <div className="flex gap-4 mt-1 text-xs" style={{ color: '#6b7280' }}>
                  <span>Cliff: {secondsToDuration(bucket.cliff)}</span>
                  <span>Vesting: {secondsToDuration(bucket.vestingDuration)}</span>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
