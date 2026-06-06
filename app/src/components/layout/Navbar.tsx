'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { cn } from '@/lib/utils'

const NAV_LINKS = [
  { href: '/',        label: 'Discover' },
  { href: '/create',  label: 'Create'   },
  { href: '/faucet',  label: 'Faucet'   },
  { href: '/profile', label: 'Profile'  },
]

export function Navbar() {
  const pathname = usePathname()

  return (
    <nav
      className="sticky top-0 z-50"
      style={{
        background: 'rgba(12,10,6,0.8)',
        backdropFilter: 'blur(20px)',
        borderBottom: '1px solid rgba(251,191,36,0.08)',
        height: '56px',
      }}
    >
      <div className="max-w-7xl mx-auto px-4 h-full flex items-center justify-between">
        {/* Logo + nav links */}
        <div className="flex items-center gap-8">
          <Link href="/" className="font-extrabold text-lg tracking-tight" style={{
            background: 'linear-gradient(90deg, #fbbf24, #f59e0b)',
            WebkitBackgroundClip: 'text',
            WebkitTextFillColor: 'transparent',
          }}>
            GradPad
          </Link>

          <div className="flex items-center gap-1">
            {NAV_LINKS.map(link => (
              <Link
                key={link.href}
                href={link.href}
                className={cn(
                  'px-3 py-1.5 rounded-lg text-sm font-medium transition-colors',
                  pathname === link.href
                    ? 'text-white'
                    : 'text-muted-foreground hover:text-white'
                )}
                style={
                  pathname === link.href
                    ? { background: 'rgba(255,255,255,0.08)' }
                    : undefined
                }
              >
                {link.label}
              </Link>
            ))}
          </div>
        </div>

        {/* Wallet connect */}
        <ConnectButton />
      </div>
    </nav>
  )
}
