'use client'

import { useAccount } from 'wagmi'
import { useQuery } from 'urql'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { USER_TOKENS_QUERY, USER_TRADES_QUERY } from '@/lib/queries'
import { TokenCard } from '@/components/discover/TokenCard'
import { GradPadToken, Trade, Phase } from '@/types'
import Link from 'next/link'
import { formatDecimal, shortenAddress } from '@/lib/utils'

interface TradeWithToken extends Trade {
  token: { id: string; name: string; symbol: string }
}

export default function ProfilePage() {
  const { address, isConnected } = useAccount()

  const [{ data: tokensData }] = useQuery<{ gradPadTokens: GradPadToken[] }>({
    query: USER_TOKENS_QUERY,
    variables: { creator: address?.toLowerCase() },
    pause: !address,
  })

  const [{ data: tradesData }] = useQuery<{ trades: TradeWithToken[] }>({
    query: USER_TRADES_QUERY,
    variables: { trader: address?.toLowerCase() },
    pause: !address,
  })

  if (!isConnected) {
    return (
      <main
        className="flex flex-col items-center justify-center min-h-screen gap-6"
        style={{ background: '#0c0a06' }}
      >
        <div className="text-center space-y-2">
          <h1 className="text-2xl font-extrabold text-white">Your Profile</h1>
          <p className="text-sm text-muted-foreground">Connect your wallet to view your profile.</p>
        </div>
        <ConnectButton />
      </main>
    )
  }

  const createdTokens: GradPadToken[] = tokensData?.gradPadTokens ?? []
  const recentTrades: TradeWithToken[] = tradesData?.trades ?? []

  return (
    <main
      className="max-w-5xl mx-auto px-4 py-8 space-y-10"
      style={{ minHeight: '100vh' }}
    >
      {/* Header */}
      <div>
        <h1 className="text-2xl font-extrabold text-white tracking-tight">{shortenAddress(address!)}</h1>
        <p className="text-sm text-muted-foreground">Base Mainnet</p>
      </div>

      {/* Tokens launched */}
      <section className="space-y-4">
        <h2 className="text-lg font-bold text-white">Tokens Launched</h2>
        {createdTokens.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No tokens launched yet.{' '}
            <Link href="/create" style={{ color: '#fbbf24' }} className="hover:underline">
              Launch one →
            </Link>
          </p>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {createdTokens.map(t => <TokenCard key={t.id} token={t} />)}
          </div>
        )}
      </section>

      {/* Recent trades */}
      <section className="space-y-4">
        <h2 className="text-lg font-bold text-white">Recent Trades</h2>
        {recentTrades.length === 0 ? (
          <p className="text-sm text-muted-foreground">No trades yet.</p>
        ) : (
          <div
            className="rounded-2xl overflow-hidden"
            style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.07)' }}
          >
            <table className="w-full text-sm">
              <thead style={{ background: 'rgba(255,255,255,0.03)' }}>
                <tr>
                  {['Token', 'Side', 'Amount In', 'Amount Out', 'Phase'].map(h => (
                    <th
                      key={h}
                      className="text-left px-4 py-3 text-xs font-semibold uppercase tracking-wider"
                      style={{ color: '#6b7280' }}
                    >
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {recentTrades.map((trade, i) => (
                  <tr
                    key={trade.id}
                    style={{ borderTop: i > 0 ? '1px solid rgba(255,255,255,0.06)' : undefined }}
                  >
                    <td className="px-4 py-3">
                      <Link
                        href={`/token/${trade.token.id}`}
                        className="font-medium hover:underline"
                        style={{ color: '#fbbf24' }}
                      >
                        {trade.token.symbol}
                      </Link>
                    </td>
                    <td className="px-4 py-3 font-medium" style={{ color: trade.isBuy ? '#34d399' : '#f87171' }}>
                      {trade.isBuy ? 'Buy' : 'Sell'}
                    </td>
                    <td className="px-4 py-3 text-white">{formatDecimal(trade.amountIn)}</td>
                    <td className="px-4 py-3 text-white">{formatDecimal(trade.amountOut)}</td>
                    <td className="px-4 py-3">
                      <span
                        className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded"
                        style={
                          trade.phase === ('bonding' as Phase)
                            ? { background: 'rgba(251,191,36,0.12)', border: '1px solid rgba(251,191,36,0.2)', color: '#fbbf24' }
                            : { background: 'rgba(16,185,129,0.12)', border: '1px solid rgba(16,185,129,0.2)', color: '#34d399' }
                        }
                      >
                        {trade.phase}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </main>
  )
}
