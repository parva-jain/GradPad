import Link from 'next/link'
import { GradPadToken } from '@/types'
import { formatDecimal } from '@/lib/utils'

interface Props {
  token: GradPadToken
}

const GRADUATION_THRESHOLD = 100_000 // USDC

export function TokenCard({ token }: Props) {
  const progress = Math.min((parseFloat(token.totalVolume) / GRADUATION_THRESHOLD) * 100, 100)
  const isGraduated = !token.bondingPhase

  return (
    <>
      <style>{`
        .token-card {
          position: relative;
          background: rgba(255,255,255,0.025);
          border: 1px solid rgba(255,255,255,0.07);
          border-radius: 16px;
          overflow: hidden;
          transition: border-color 0.2s ease, transform 0.2s ease, box-shadow 0.2s ease;
          text-decoration: none;
          display: block;
        }
        .token-card::before {
          content: '';
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 1px;
          background: linear-gradient(90deg, transparent, rgba(251,191,36,0.2), transparent);
        }
        .token-card:hover {
          border-color: rgba(251,191,36,0.2);
          transform: translateY(-1px);
          box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        .progress-bar-bonding {
          background: linear-gradient(90deg, #d97706, #fbbf24);
          box-shadow: 0 0 8px rgba(251,191,36,0.4);
        }
        .progress-bar-graduated {
          background: linear-gradient(90deg, #059669, #34d399);
        }
      `}</style>
      <Link href={`/token/${token.id}`} className="token-card">
        <div className="p-5 flex flex-col gap-4">
          {/* Top row: name/symbol + badge */}
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p
                className="text-white font-bold leading-tight truncate"
                style={{ fontSize: '15px', fontWeight: 700 }}
              >
                {token.name}
              </p>
              <p
                className="text-muted-foreground truncate"
                style={{ fontSize: '11px', marginTop: '2px' }}
              >
                {token.symbol}
              </p>
            </div>
            {isGraduated ? (
              <span
                className="shrink-0 rounded-md px-2 py-0.5 font-bold tracking-widest"
                style={{
                  background: 'rgba(16,185,129,0.12)',
                  border: '1px solid rgba(16,185,129,0.2)',
                  color: '#34d399',
                  fontSize: '9px',
                  fontWeight: 700,
                  textTransform: 'uppercase',
                  letterSpacing: '0.08em',
                }}
              >
                GRADUATED
              </span>
            ) : (
              <span
                className="shrink-0 rounded-md px-2 py-0.5 font-bold tracking-widest"
                style={{
                  background: 'rgba(251,191,36,0.12)',
                  border: '1px solid rgba(251,191,36,0.2)',
                  color: '#fbbf24',
                  fontSize: '9px',
                  fontWeight: 700,
                  textTransform: 'uppercase',
                  letterSpacing: '0.08em',
                }}
              >
                BONDING
              </span>
            )}
          </div>

          {/* Progress section */}
          <div className="flex flex-col gap-1.5">
            <div className="flex items-center justify-between">
              <span
                className="text-muted-foreground"
                style={{ fontSize: '10px', textTransform: 'uppercase', letterSpacing: '0.06em' }}
              >
                Progress
              </span>
              <span
                className="text-muted-foreground"
                style={{ fontSize: '10px' }}
              >
                {progress.toFixed(1)}%
              </span>
            </div>
            {/* Progress bar track */}
            <div
              className="w-full rounded-full overflow-hidden"
              style={{
                height: '5px',
                background: 'rgba(255,255,255,0.06)',
              }}
            >
              <div
                className={isGraduated ? 'progress-bar-graduated' : 'progress-bar-bonding'}
                style={{
                  height: '100%',
                  width: `${progress}%`,
                  borderRadius: '9999px',
                  transition: 'width 0.4s ease',
                }}
              />
            </div>
          </div>

          {/* Stats row */}
          <div
            className="flex items-center justify-between rounded-xl px-3 py-2.5"
            style={{
              background: 'rgba(255,255,255,0.03)',
              border: '1px solid rgba(251,191,36,0.1)',
            }}
          >
            <div className="flex flex-col gap-0.5">
              <span
                className="text-muted-foreground"
                style={{ fontSize: '10px', textTransform: 'uppercase', letterSpacing: '0.06em' }}
              >
                Volume
              </span>
              <span className="text-white font-bold" style={{ fontSize: '13px', fontWeight: 700 }}>
                ${formatDecimal(token.totalVolume)}
              </span>
            </div>
            <div
              className="w-px self-stretch"
              style={{ background: 'rgba(255,255,255,0.06)' }}
            />
            <div className="flex flex-col gap-0.5 items-end">
              <span
                className="text-muted-foreground"
                style={{ fontSize: '10px', textTransform: 'uppercase', letterSpacing: '0.06em' }}
              >
                Trades
              </span>
              <span className="text-white font-bold" style={{ fontSize: '13px', fontWeight: 700 }}>
                {parseInt(token.tradeCount).toLocaleString()}
              </span>
            </div>
          </div>
        </div>
      </Link>
    </>
  )
}
