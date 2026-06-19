import { ImageResponse } from 'next/og'

export const runtime = 'edge'
export const alt = 'GradPad — Token Launchpad on Base'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          background: '#0c0a06',
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'flex-start',
          justifyContent: 'center',
          padding: '80px 90px',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        {/* Amber glow top-left */}
        <div
          style={{
            position: 'absolute',
            top: -100,
            left: -100,
            width: 700,
            height: 500,
            borderRadius: '50%',
            background: 'radial-gradient(ellipse, rgba(251,191,36,0.18) 0%, transparent 70%)',
          }}
        />
        {/* Subtle glow bottom-right */}
        <div
          style={{
            position: 'absolute',
            bottom: -80,
            right: -80,
            width: 500,
            height: 400,
            borderRadius: '50%',
            background: 'radial-gradient(ellipse, rgba(251,191,36,0.08) 0%, transparent 70%)',
          }}
        />

        {/* Logo wordmark */}
        <div
          style={{
            fontSize: 44,
            fontWeight: 900,
            color: '#fbbf24',
            letterSpacing: '-1px',
            marginBottom: 36,
          }}
        >
          GradPad
        </div>

        {/* Headline */}
        <div
          style={{
            fontSize: 72,
            fontWeight: 800,
            color: '#ffffff',
            lineHeight: 1.08,
            letterSpacing: '-2px',
            maxWidth: 900,
            marginBottom: 32,
          }}
        >
          Launch tokens with built-in liquidity
        </div>

        {/* Subline */}
        <div
          style={{
            fontSize: 30,
            color: 'rgba(255,255,255,0.45)',
            letterSpacing: '-0.5px',
          }}
        >
          Bonding curve → Uniswap V2 · No upfront capital · Built on Base
        </div>

        {/* Pill badges */}
        <div
          style={{
            display: 'flex',
            gap: 12,
            marginTop: 48,
          }}
        >
          {['Bonding Curve', 'Auto Graduation', 'On-chain Vesting'].map(label => (
            <div
              key={label}
              style={{
                padding: '8px 20px',
                borderRadius: 999,
                background: 'rgba(251,191,36,0.1)',
                border: '1px solid rgba(251,191,36,0.25)',
                color: '#fbbf24',
                fontSize: 18,
                fontWeight: 600,
              }}
            >
              {label}
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  )
}
