'use client'

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { Trade } from '@/types'
import { formatDecimal } from '@/lib/utils'

interface Props {
  trades: Trade[]
}

export function PriceChart({ trades }: Props) {
  const data = trades.map(t => ({
    time: new Date(parseInt(t.timestamp) * 1000).toLocaleDateString(),
    price: parseFloat(t.price),
  }))

  if (data.length === 0) {
    return (
      <div
        className="h-64 w-full rounded-2xl flex items-center justify-center"
        style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
      >
        <p className="text-sm text-muted-foreground">No trades yet</p>
      </div>
    )
  }

  return (
    <div
      className="h-64 w-full rounded-2xl p-4"
      style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
    >
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
          <XAxis dataKey="time" tick={{ fontSize: 11, fill: '#6b7280' }} stroke="rgba(255,255,255,0.05)" />
          <YAxis
            tick={{ fontSize: 11, fill: '#6b7280' }}
            stroke="rgba(255,255,255,0.05)"
            tickFormatter={v => formatDecimal(v.toString(), 4)}
          />
          <Tooltip
            contentStyle={{
              background: '#18181b',
              border: '1px solid rgba(251,191,36,0.2)',
              borderRadius: '8px',
              color: '#fff',
            }}
            // @ts-expect-error — recharts v3 ValueType is wider than number
            formatter={(v: number) => [`$${v.toFixed(6)}`, 'Price']}
          />
          <Line
            type="monotone"
            dataKey="price"
            stroke="#fbbf24"
            strokeWidth={2}
            dot={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
