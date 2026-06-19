'use client'

import { useParams } from 'next/navigation'
import { useQuery } from 'urql'
import { useReadContracts } from 'wagmi'
import { formatUnits } from 'viem'
import { TOKEN_DETAIL_QUERY } from '@/lib/queries'
import { GradPadToken } from '@/types'
import { PriceChart } from '@/components/token-detail/PriceChart'
import { BondingProgressBar } from '@/components/token-detail/BondingProgressBar'
import { AllocationPanel } from '@/components/token-detail/AllocationPanel'
import { TokenInfoPanel } from '@/components/token-detail/TokenInfoPanel'
import { RecentTradesPanel } from '@/components/token-detail/RecentTradesPanel'
import { BondingTradePanel } from '@/components/token-detail/BondingTradePanel'
import { UniswapTradePanel } from '@/components/token-detail/UniswapTradePanel'
import { ClaimPanel } from '@/components/token-detail/ClaimPanel'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { formatDecimal, shortenAddress, formatUrqlError } from '@/lib/utils'

const TOKEN_SUPPLY_ABI = [
  { name: 'totalSupply', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const

const UNI_PAIR_ABI = [
  {
    name: 'getReserves',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'reserve0', type: 'uint112' },
      { name: 'reserve1', type: 'uint112' },
      { name: 'blockTimestampLast', type: 'uint32' },
    ],
  },
  {
    name: 'token0',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'address' }],
  },
] as const

function fmtUSD(n: number): string {
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`
  if (n >= 1_000) return `$${(n / 1_000).toFixed(2)}K`
  if (n >= 1) return `$${n.toFixed(4)}`
  if (n >= 0.0001) return `$${n.toFixed(6)}`
  return `$${n.toExponential(3)}`
}

function fmtSupply(n: number): string {
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(0)}B`
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(0)}M`
  return n.toLocaleString(undefined, { maximumFractionDigits: 0 })
}

export default function TokenDetailPage() {
  const { address } = useParams<{ address: string }>()

  const [{ data, fetching, error }, reexecuteQuery] = useQuery<{ gradPadToken: GradPadToken }>({
    query: TOKEN_DETAIL_QUERY,
    variables: { address: address.toLowerCase() },
  })

  // On-chain reads: price + total supply
  const token = data?.gradPadToken
  const uniswapPair = token?.uniswapPair
  const hasUniPair =
    !!uniswapPair && uniswapPair !== '0x0000000000000000000000000000000000000000'

  const { data: baseChain } = useReadContracts({
    contracts: [
      {
        address: address as `0x${string}`,
        abi: TOKEN_SUPPLY_ABI,
        functionName: 'totalSupply' as const,
      },
      {
        address: ADDRESSES.GradPadFactory,
        abi: ABIS.GradPadFactory,
        functionName: 'getPriceWAD' as const,
        args: [address as `0x${string}`] as const,
      },
    ] as const,
    query: { enabled: !!address },
  })

  // Uniswap pair reserves (only when graduated and pair exists)
  const { data: uniChain } = useReadContracts({
    contracts: [
      {
        address: (hasUniPair ? uniswapPair : ADDRESSES.GradPadFactory) as `0x${string}`,
        abi: UNI_PAIR_ABI,
        functionName: 'getReserves' as const,
      },
      {
        address: (hasUniPair ? uniswapPair : ADDRESSES.GradPadFactory) as `0x${string}`,
        abi: UNI_PAIR_ABI,
        functionName: 'token0' as const,
      },
    ] as const,
    query: { enabled: hasUniPair },
  })

  function onTradeSuccess() {
    setTimeout(() => reexecuteQuery({ requestPolicy: 'network-only' }), 12_000)
    setTimeout(() => reexecuteQuery({ requestPolicy: 'network-only' }), 30_000)
  }

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
  if (!token) return (
    <div className="flex items-center justify-center min-h-screen">
      <p className="text-muted-foreground">Token not found</p>
    </div>
  )

  // Derive price and metrics
  const totalSupplyRaw = baseChain?.[0]?.result as bigint | undefined
  const priceWAD       = baseChain?.[1]?.result as bigint | undefined
  const reserves       = uniChain?.[0]?.result as [bigint, bigint, number] | undefined
  const uniToken0      = uniChain?.[1]?.result as string | undefined

  const totalSupply = totalSupplyRaw ? Number(formatUnits(totalSupplyRaw, 18)) : 1_000_000_000

  // Price: bonding = getPriceWAD / 1e18 (WAD-normalised, 1e18 = 1 USDC)
  //        graduated = Uniswap reserves ratio
  let priceUSDC: number | null = null
  if (token.bondingPhase && priceWAD) {
    priceUSDC = Number(formatUnits(priceWAD, 18))
  } else if (!token.bondingPhase && reserves && uniToken0) {
    const isGP0 = uniToken0.toLowerCase() === address.toLowerCase()
    const gpRes   = isGP0 ? reserves[0] : reserves[1]
    const usdcRes = isGP0 ? reserves[1] : reserves[0]
    if (gpRes > BigInt(0)) {
      priceUSDC = (Number(usdcRes) / 1e6) / (Number(gpRes) / 1e18)
    }
  }
  if (!priceUSDC && token.trades && token.trades.length > 0) {
    priceUSDC = parseFloat(token.trades[token.trades.length - 1].price)
  }

  const marketCap = priceUSDC ? priceUSDC * totalSupply : null

  return (
    <main className="max-w-7xl mx-auto px-4 py-8" style={{ minHeight: '100vh' }}>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

        {/* ── Left column ── */}
        <div className="lg:col-span-2 space-y-6">

          {/* Token header */}
          <div className="space-y-3">
            <div className="flex items-start justify-between">
              <div>
                <h1 className="text-2xl font-extrabold text-white tracking-tight">{token.name}</h1>
                <p className="text-sm text-muted-foreground">{token.symbol}</p>
              </div>
              <span
                className="text-xs font-bold uppercase tracking-wider px-2 py-1 rounded shrink-0"
                style={
                  token.bondingPhase
                    ? { background: 'rgba(251,191,36,0.12)', border: '1px solid rgba(251,191,36,0.2)', color: '#fbbf24' }
                    : { background: 'rgba(16,185,129,0.12)', border: '1px solid rgba(16,185,129,0.2)', color: '#34d399' }
                }
              >
                {token.bondingPhase ? 'Bonding' : 'Graduated'}
              </span>
            </div>

            {/* Price hero */}
            {priceUSDC && (
              <div className="flex items-baseline gap-3">
                <span className="text-3xl font-extrabold text-white tracking-tight">
                  {fmtUSD(priceUSDC)}
                </span>
                <span className="text-sm" style={{ color: '#6b7280' }}>per {token.symbol}</span>
              </div>
            )}
          </div>

          {/* Price chart */}
          <PriceChart trades={token.trades ?? []} />

          {/* Bonding progress */}
          <BondingProgressBar bondingPhase={token.bondingPhase} tokenAddress={token.id} />

          {/* Metrics grid */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {[
              {
                label: 'Price',
                value: priceUSDC ? fmtUSD(priceUSDC) : '—',
              },
              {
                label: 'Market Cap',
                value: marketCap ? fmtUSD(marketCap) : '—',
              },
              {
                label: 'Total Supply',
                value: fmtSupply(totalSupply),
              },
              {
                label: 'Volume',
                value: `$${formatDecimal(token.totalVolume)}`,
              },
              {
                label: 'Trades',
                value: parseInt(token.tradeCount).toLocaleString(),
              },
              {
                label: 'Creator',
                value: shortenAddress(token.creator),
              },
              {
                label: 'Created',
                value: new Date(parseInt(token.createdAt) * 1000).toLocaleDateString(),
              },
              {
                label: 'Graduated',
                value: token.graduatedAt
                  ? new Date(parseInt(token.graduatedAt) * 1000).toLocaleDateString()
                  : '—',
              },
            ].map(stat => (
              <div
                key={stat.label}
                className="rounded-xl p-3"
                style={{
                  background: 'rgba(255,255,255,0.03)',
                  border: '1px solid rgba(251,191,36,0.08)',
                }}
              >
                <p className="text-xs font-semibold uppercase tracking-wider" style={{ color: '#6b7280' }}>
                  {stat.label}
                </p>
                <p className="text-sm font-bold text-white mt-0.5 truncate">{stat.value}</p>
              </div>
            ))}
          </div>

          {/* Contract addresses */}
          <TokenInfoPanel
            tokenAddress={token.id}
            creator={token.creator}
            uniswapPair={token.uniswapPair}
          />

          {/* Token allocation */}
          {token.buckets.length > 0 && (
            <AllocationPanel
              tokenAddress={token.id as `0x${string}`}
              buckets={token.buckets}
              bondingPhase={token.bondingPhase}
              graduatedAt={token.graduatedAt}
              totalSupply={totalSupply}
            />
          )}
        </div>

        {/* ── Right column ── */}
        <div className="lg:col-span-1 space-y-4">
          <div className="space-y-4">
            {token.bondingPhase && (
              <BondingTradePanel
                tokenAddress={token.id as `0x${string}`}
                tokenSymbol={token.symbol}
                onTradeSuccess={onTradeSuccess}
              />
            )}
            {!token.bondingPhase && (
              <UniswapTradePanel
                tokenAddress={token.id as `0x${string}`}
                tokenSymbol={token.symbol}
                uniswapPair={token.uniswapPair ?? ''}
              />
            )}
            {token.buckets.length > 0 && (
              <ClaimPanel
                tokenAddress={token.id as `0x${string}`}
                tokenSymbol={token.symbol}
                buckets={token.buckets}
                graduatedAt={token.graduatedAt}
                totalSupply={totalSupply}
              />
            )}
          </div>

          {/* Recent trades */}
          {(token.trades ?? []).length > 0 && (
            <RecentTradesPanel
              trades={token.trades ?? []}
              tokenSymbol={token.symbol}
            />
          )}
        </div>

      </div>
    </main>
  )
}
