'use client'

import { useParams } from 'next/navigation'
import { useQuery } from 'urql'
import { TOKEN_DETAIL_QUERY } from '@/lib/queries'
import { GradPadToken } from '@/types'
import { PriceChart } from '@/components/token-detail/PriceChart'
import { BondingProgressBar } from '@/components/token-detail/BondingProgressBar'
import { VestingTimeline } from '@/components/token-detail/VestingTimeline'
import { formatDecimal, shortenAddress, formatUrqlError } from '@/lib/utils'
import { BondingTradePanel } from '@/components/token-detail/BondingTradePanel'
import { UniswapTradePanel } from '@/components/token-detail/UniswapTradePanel'
import { ClaimPanel } from '@/components/token-detail/ClaimPanel'

export default function TokenDetailPage() {
  const { address } = useParams<{ address: string }>()

  const [{ data, fetching, error }] = useQuery<{ gradPadToken: GradPadToken }>({
    query: TOKEN_DETAIL_QUERY,
    variables: { address: address.toLowerCase() },
  })

  if (fetching) return (
    <div className="flex items-center justify-center min-h-screen">
      <p className="text-muted-foreground">Loading...</p>
    </div>
  )
  if (error) return (
    <div className="flex flex-col items-center justify-center min-h-screen gap-2">
      <p className="text-red-400 font-semibold">Failed to load token</p>
      <p className="text-sm text-muted-foreground">{formatUrqlError(error)}</p>
    </div>
  )
  if (!data?.gradPadToken) return (
    <div className="flex items-center justify-center min-h-screen">
      <p className="text-muted-foreground">Token not found</p>
    </div>
  )

  const token = data.gradPadToken

  return (
    <main
      className="max-w-7xl mx-auto px-4 py-8"
      style={{ minHeight: '100vh' }}
    >
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Left column — chart + stats + tokenomics */}
        <div className="lg:col-span-2 space-y-6">
          {/* Token header */}
          <div className="flex items-start justify-between">
            <div>
              <h1 className="text-2xl font-extrabold text-white tracking-tight">{token.name}</h1>
              <p className="text-sm text-muted-foreground">{token.symbol}</p>
            </div>
            <div className="flex items-center gap-2">
              <span
                className="text-xs font-bold uppercase tracking-wider px-2 py-1 rounded"
                style={
                  token.bondingPhase
                    ? { background: 'rgba(251,191,36,0.12)', border: '1px solid rgba(251,191,36,0.2)', color: '#fbbf24' }
                    : { background: 'rgba(16,185,129,0.12)', border: '1px solid rgba(16,185,129,0.2)', color: '#34d399' }
                }
              >
                {token.bondingPhase ? 'Bonding' : 'Graduated'}
              </span>
            </div>
          </div>

          {/* Price chart */}
          <PriceChart trades={token.trades ?? []} />

          {/* Bonding progress */}
          <BondingProgressBar
            bondingPhase={token.bondingPhase}
            totalVolume={token.totalVolume}
          />

          {/* Token stats */}
          <div
            className="grid grid-cols-2 sm:grid-cols-4 gap-3"
          >
            {[
              { label: 'Creator', value: shortenAddress(token.creator) },
              { label: 'Volume', value: `$${formatDecimal(token.totalVolume)}` },
              { label: 'Trades', value: token.tradeCount },
              { label: 'Created', value: new Date(parseInt(token.createdAt) * 1000).toLocaleDateString() },
            ].map(stat => (
              <div
                key={stat.label}
                className="rounded-xl p-3"
                style={{
                  background: 'rgba(255,255,255,0.03)',
                  border: '1px solid rgba(251,191,36,0.1)',
                }}
              >
                <p className="text-xs font-semibold uppercase tracking-wider" style={{ color: '#6b7280' }}>
                  {stat.label}
                </p>
                <p className="text-sm font-bold text-white mt-0.5">{stat.value}</p>
              </div>
            ))}
          </div>

          {/* Tokenomics / vesting */}
          {token.buckets.length > 0 && (
            <div
              className="rounded-2xl p-5 space-y-4"
              style={{
                background: 'rgba(255,255,255,0.025)',
                border: '1px solid rgba(255,255,255,0.07)',
              }}
            >
              <h2 className="text-base font-bold text-white">Tokenomics</h2>
              <div className="space-y-4">
                {token.buckets.map(bucket => (
                  <VestingTimeline key={bucket.id} bucket={bucket} graduatedAt={token.graduatedAt} />
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Right column — Trade panel */}
        <div className="lg:col-span-1">
          <div className="sticky top-20 space-y-4">
            {token.bondingPhase && (
              <BondingTradePanel
                tokenAddress={token.id as `0x${string}`}
                tokenSymbol={token.symbol}
              />
            )}
            {!token.bondingPhase && (
              <UniswapTradePanel
                tokenAddress={token.id as `0x${string}`}
                tokenSymbol={token.symbol}
                uniswapPair={token.uniswapPair ?? ''}
              />
            )}
            <ClaimPanel
              tokenAddress={token.id as `0x${string}`}
              buckets={token.buckets}
              graduatedAt={token.graduatedAt}
            />
          </div>
        </div>
      </div>
    </main>
  )
}
