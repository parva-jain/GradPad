'use client'

import { useQuery } from 'urql'
import { useState } from 'react'
import { TOKENS_QUERY } from '@/lib/queries'
import { TokenGrid } from '@/components/discover/TokenGrid'
import { GradPadToken } from '@/types'

type SortField = 'createdAt' | 'totalVolume' | 'tradeCount'

export default function DiscoverPage() {
  const [sortBy, setSortBy] = useState<SortField>('createdAt')

  const [{ data, fetching, error }] = useQuery<{ gradPadTokens: GradPadToken[] }>({
    query: TOKENS_QUERY,
    variables: { first: 50, orderBy: sortBy, orderDirection: 'desc' },
  })

  return (
    <main className="relative min-h-screen" style={{ background: '#0c0a06' }}>
      {/* Ambient page glow */}
      <div
        className="fixed inset-0 pointer-events-none"
        style={{
          background:
            'radial-gradient(ellipse 60% 40% at 20% 0%, rgba(251,191,36,0.07) 0%, transparent 60%), radial-gradient(ellipse 40% 30% at 80% 100%, rgba(251,191,36,0.04) 0%, transparent 60%)',
          zIndex: 0,
        }}
      />
      <div className="relative z-10 max-w-7xl mx-auto px-4 py-8">
        {/* Page header */}
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-extrabold text-white tracking-tight">Discover Tokens</h1>
            <p className="text-sm text-muted-foreground mt-1">Find and trade tokens on Base mainnet</p>
          </div>
          <SortControls value={sortBy} onChange={setSortBy} />
        </div>

        {/* Loading / error / grid */}
        {fetching && (
          <div className="text-center py-24 text-muted-foreground">Loading tokens...</div>
        )}
        {error && (
          <div className="text-center py-24 text-red-400">Error: {error.message}</div>
        )}
        {!fetching && !error && (
          <TokenGrid tokens={data?.gradPadTokens ?? []} />
        )}
      </div>
    </main>
  )
}

function SortControls({ value, onChange }: { value: SortField; onChange: (v: SortField) => void }) {
  const options: { label: string; value: SortField }[] = [
    { label: 'Newest', value: 'createdAt' },
    { label: 'Volume', value: 'totalVolume' },
    { label: 'Trades', value: 'tradeCount' },
  ]
  return (
    <div
      className="flex items-center p-1 rounded-xl"
      style={{
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.06)',
      }}
    >
      {options.map(o => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className="px-3 py-1.5 rounded-lg text-sm font-medium transition-all"
          style={
            value === o.value
              ? { background: 'rgba(251,191,36,0.12)', color: '#fbbf24' }
              : { color: '#6b7280' }
          }
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}
