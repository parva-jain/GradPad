'use client'

import { useState } from 'react'
import { Trade } from '@/types'
import { shortenAddress } from '@/lib/utils'

const PAGE_SIZE = 10

function timeAgo(timestamp: string): string {
  const diff = Math.floor(Date.now() / 1000) - parseInt(timestamp)
  if (diff < 60)    return `${diff}s`
  if (diff < 3600)  return `${Math.floor(diff / 60)}m`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`
  return `${Math.floor(diff / 86400)}d`
}

function fmtToken(val: string): string {
  const n = parseFloat(val)
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`
  if (n >= 1_000)     return `${(n / 1_000).toFixed(1)}K`
  if (n >= 1)         return n.toFixed(2)
  return n.toFixed(4)
}

function fmtUSDC(val: string): string {
  const n = parseFloat(val)
  if (n >= 1_000) return `$${(n / 1_000).toFixed(2)}K`
  if (n >= 1)     return `$${n.toFixed(2)}`
  return `$${n.toFixed(4)}`
}

function fmtPrice(val: string): string {
  const n = parseFloat(val)
  if (n >= 1)       return `$${n.toFixed(4)}`
  if (n >= 0.00001) return `$${n.toFixed(6)}`
  return `$${n.toExponential(3)}`
}

interface Props {
  trades: Trade[]
  tokenSymbol: string
}

export function RecentTradesPanel({ trades, tokenSymbol }: Props) {
  const [page, setPage] = useState(0)

  const sorted     = [...trades].reverse()   // newest first
  const totalPages = Math.ceil(sorted.length / PAGE_SIZE)
  const pageData   = sorted.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)

  if (trades.length === 0) return null

  return (
    <div
      className="rounded-2xl overflow-hidden"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(255,255,255,0.07)',
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: '1px solid rgba(255,255,255,0.06)' }}
      >
        <h2 className="text-sm font-bold text-white">Recent Trades</h2>
        <span className="text-xs" style={{ color: '#6b7280' }}>
          {trades.length} total
        </span>
      </div>

      {/* Trade rows */}
      <div>
        {pageData.map((trade, i) => {
          const isBuy    = trade.isBuy
          const tokenAmt = isBuy ? trade.amountOut : trade.amountIn
          const usdcAmt  = isBuy ? trade.amountIn  : trade.amountOut

          return (
            <div
              key={trade.id}
              className="px-4 py-2.5"
              style={{
                borderBottom: i < pageData.length - 1
                  ? '1px solid rgba(255,255,255,0.04)'
                  : 'none',
                background: i % 2 === 0 ? 'transparent' : 'rgba(255,255,255,0.01)',
              }}
            >
              {/* Top line: type + tokens + value */}
              <div className="flex items-center gap-2">
                {/* Type pill */}
                <span
                  className="shrink-0 text-xs font-bold rounded px-1.5 py-0.5"
                  style={{
                    background: isBuy ? 'rgba(16,185,129,0.15)' : 'rgba(239,68,68,0.15)',
                    color: isBuy ? '#34d399' : '#f87171',
                    border: `1px solid ${isBuy ? 'rgba(16,185,129,0.3)' : 'rgba(239,68,68,0.3)'}`,
                    minWidth: 36,
                    textAlign: 'center',
                  }}
                >
                  {isBuy ? 'BUY' : 'SELL'}
                </span>

                {/* Token amount */}
                <span
                  className="text-xs font-semibold tabular-nums truncate flex-1"
                  style={{ color: isBuy ? '#34d399' : '#f87171' }}
                >
                  {fmtToken(tokenAmt)}{' '}
                  <span style={{ opacity: 0.6 }}>{tokenSymbol}</span>
                </span>

                {/* USDC value */}
                <span
                  className="text-xs font-bold tabular-nums shrink-0 text-white"
                >
                  {fmtUSDC(usdcAmt)}
                </span>
              </div>

              {/* Bottom line: price · time · maker */}
              <div
                className="flex items-center gap-1.5 mt-0.5 pl-0.5 text-xs"
                style={{ color: '#4b5563' }}
              >
                <span className="tabular-nums">{fmtPrice(trade.price)}</span>
                <span>·</span>
                <span className="tabular-nums">{timeAgo(trade.timestamp)}</span>
                {trade.trader && (
                  <>
                    <span>·</span>
                    <a
                      href={`https://basescan.org/address/${trade.trader}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="font-mono hover:text-white transition-colors"
                    >
                      {shortenAddress(trade.trader)}
                    </a>
                  </>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div
          className="flex items-center justify-between px-4 py-2.5"
          style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}
        >
          <button
            onClick={() => setPage(p => Math.max(0, p - 1))}
            disabled={page === 0}
            className="text-xs px-2.5 py-1 rounded-lg font-medium"
            style={{
              background: page === 0 ? 'rgba(255,255,255,0.03)' : 'rgba(255,255,255,0.08)',
              color: page === 0 ? '#374151' : '#e5e7eb',
              border: '1px solid rgba(255,255,255,0.08)',
              cursor: page === 0 ? 'not-allowed' : 'pointer',
            }}
          >
            ← Prev
          </button>
          <span className="text-xs" style={{ color: '#6b7280' }}>
            {page + 1} / {totalPages}
          </span>
          <button
            onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))}
            disabled={page >= totalPages - 1}
            className="text-xs px-2.5 py-1 rounded-lg font-medium"
            style={{
              background: page >= totalPages - 1 ? 'rgba(255,255,255,0.03)' : 'rgba(255,255,255,0.08)',
              color: page >= totalPages - 1 ? '#374151' : '#e5e7eb',
              border: '1px solid rgba(255,255,255,0.08)',
              cursor: page >= totalPages - 1 ? 'not-allowed' : 'pointer',
            }}
          >
            Next →
          </button>
        </div>
      )}
    </div>
  )
}
