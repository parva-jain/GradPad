'use client'

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { Trade } from '@/types'

function formatPrice(v: number): string {
  if (v === 0) return '0'
  if (v < 0.001) return v.toExponential(2)   // e.g. 1.23e-4
  if (v < 0.1)   return v.toFixed(4)          // e.g. 0.0012
  if (v < 1000)  return v.toFixed(2)          // e.g. 12.34
  return `${(v / 1000).toFixed(1)}K`
}

interface Props {
  trades: Trade[]
}

export function PriceChart({ trades }: Props) {
  if (trades.length === 0) {
    return (
      <div
        className="h-64 w-full rounded-2xl flex items-center justify-center"
        style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
      >
        <p className="text-sm text-muted-foreground">No trades yet</p>
      </div>
    )
  }

  const timestamps = trades.map(t => parseInt(t.timestamp))
  const spansDays = Math.max(...timestamps) - Math.min(...timestamps) > 86400

  const data = trades.map(t => {
    const d = new Date(parseInt(t.timestamp) * 1000)
    return {
      time: spansDays
        ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false }),
      price: parseFloat(t.price),
    }
  })

  const prices = data.map(d => d.price).filter(p => isFinite(p))
  const minPrice = Math.min(...prices)
  const maxPrice = Math.max(...prices)
  const range = maxPrice - minPrice
  const pad = range > 0 ? range * 0.15 : maxPrice * 0.1
  const yMin = Math.max(0, minPrice - pad)
  const yMax = maxPrice + pad

  return (
    <div
      className="h-64 w-full rounded-2xl p-4"
      style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
    >
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 4, right: 8, left: 4, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
          <XAxis
            dataKey="time"
            tick={{ fontSize: 10, fill: '#6b7280' }}
            stroke="rgba(255,255,255,0.05)"
            tickLine={false}
            minTickGap={48}
          />
          <YAxis
            domain={[yMin, yMax]}
            tick={{ fontSize: 10, fill: '#6b7280' }}
            stroke="rgba(255,255,255,0.05)"
            tickLine={false}
            tickFormatter={formatPrice}
            tickCount={5}
            width={68}
          />
          <Tooltip
            contentStyle={{
              background: '#18181b',
              border: '1px solid rgba(251,191,36,0.2)',
              borderRadius: '8px',
              color: '#fff',
              fontSize: 12,
            }}
            // @ts-expect-error — recharts v3 ValueType is wider than number
            formatter={(v: number) => [`$${formatPrice(v)}`, 'Price']}
            labelStyle={{ color: '#9ca3af', marginBottom: 4 }}
          />
          <Line
            type="monotone"
            dataKey="price"
            stroke="#fbbf24"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4, fill: '#fbbf24', stroke: '#0c0a06', strokeWidth: 2 }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
