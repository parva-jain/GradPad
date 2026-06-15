'use client'

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { Trade } from '@/types'

function formatPrice(v: number): string {
  if (v === 0) return '0'
  if (v < 0.000001) return v.toExponential(2)
  if (v < 0.0001)   return v.toFixed(7)
  if (v < 0.01)     return v.toFixed(5)
  if (v < 1)        return v.toFixed(4)
  return v.toFixed(2)
}

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

  const prices = data.map(d => d.price).filter(p => isFinite(p))
  const minPrice = Math.min(...prices)
  const maxPrice = Math.max(...prices)
  const range = maxPrice - minPrice
  // 15% padding above/below; if all prices are equal use 10% of the value
  const pad = range > 0 ? range * 0.15 : maxPrice * 0.1
  const yMin = Math.max(0, minPrice - pad)
  const yMax = maxPrice + pad

  return (
    <div
      className="h-64 w-full rounded-2xl p-4"
      style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
    >
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 4, right: 8, left: 8, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
          <XAxis
            dataKey="time"
            tick={{ fontSize: 10, fill: '#6b7280' }}
            stroke="rgba(255,255,255,0.05)"
            tickLine={false}
          />
          <YAxis
            domain={[yMin, yMax]}
            tick={{ fontSize: 10, fill: '#6b7280' }}
            stroke="rgba(255,255,255,0.05)"
            tickLine={false}
            tickFormatter={formatPrice}
            width={72}
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
