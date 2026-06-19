import type { Metadata } from 'next'
import { Plus_Jakarta_Sans, Geist_Mono } from 'next/font/google'
import { Providers } from '@/components/layout/Providers'
import { Navbar } from '@/components/layout/Navbar'
import './globals.css'

const plusJakartaSans = Plus_Jakarta_Sans({
  variable: '--font-plus-jakarta-sans',
  subsets: ['latin'],
  weight: ['400', '500', '600', '700', '800'],
})

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
})

// NEXT_PUBLIC_SITE_URL → custom domain (set in Vercel env vars)
// VERCEL_URL          → auto-set by Vercel on every deployment (not NEXT_PUBLIC so server-only)
// fallback            → localhost for local dev
const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000')

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: 'GradPad — Token Launchpad on Base',
    template: '%s — GradPad',
  },
  description:
    'Launch meme and protocol tokens on Base with built-in liquidity bootstrapping. No upfront capital required — tokens start on a bonding curve and automatically graduate to Uniswap V2.',
  keywords: ['token launchpad', 'bonding curve', 'Base', 'DeFi', 'meme token', 'Uniswap'],
  openGraph: {
    type: 'website',
    siteName: 'GradPad',
    title: 'GradPad — Token Launchpad on Base',
    description:
      'Launch tokens with built-in liquidity bootstrapping. Bonding curve → Uniswap V2, no upfront capital.',
    url: SITE_URL,
    images: [{ url: '/opengraph-image', width: 1200, height: 630, alt: 'GradPad' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'GradPad — Token Launchpad on Base',
    description:
      'Launch tokens with built-in liquidity bootstrapping. Bonding curve → Uniswap V2, no upfront capital.',
    images: ['/opengraph-image'],
  },
  robots: { index: true, follow: true },
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${plusJakartaSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <Providers>
          <Navbar />
          {children}
        </Providers>
      </body>
    </html>
  )
}
