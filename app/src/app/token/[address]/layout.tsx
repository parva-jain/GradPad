import type { Metadata } from 'next'

const SUBGRAPH_URL = process.env.NEXT_PUBLIC_SUBGRAPH_URL!

async function fetchTokenMeta(address: string) {
  try {
    const res = await fetch(SUBGRAPH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        query: `{
          gradPadToken(id: "${address.toLowerCase()}") {
            name symbol bondingPhase totalVolume tradeCount
          }
        }`,
      }),
      next: { revalidate: 60 },
    })
    const json = await res.json()
    return json.data?.gradPadToken ?? null
  } catch {
    return null
  }
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ address: string }>
}): Promise<Metadata> {
  const { address } = await params
  const token = await fetchTokenMeta(address)

  if (!token) {
    return { title: 'Token Not Found' }
  }

  const status   = token.bondingPhase ? 'Bonding' : 'Graduated ✓'
  const volume   = parseFloat(token.totalVolume).toLocaleString('en-US', { maximumFractionDigits: 0 })
  const title    = `${token.name} (${token.symbol})`
  const description = `${status} · $${volume} volume · ${parseInt(token.tradeCount).toLocaleString()} trades. Trade ${token.symbol} on GradPad — the Base token launchpad.`

  return {
    title,
    description,
    openGraph: {
      title: `${title} — GradPad`,
      description,
    },
    twitter: {
      card: 'summary',
      title: `${title} — GradPad`,
      description,
    },
  }
}

export default function TokenLayout({ children }: { children: React.ReactNode }) {
  return children
}
