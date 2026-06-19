'use client'

import { useState } from 'react'
import { useReadContract } from 'wagmi'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { shortenAddress } from '@/lib/utils'

function CopyableRow({
  label,
  address,
}: {
  label: string
  address: string
}) {
  const [copied, setCopied] = useState(false)

  function copy() {
    navigator.clipboard.writeText(address)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div
      className="flex items-center justify-between py-2.5"
      style={{ borderBottom: '1px solid rgba(255,255,255,0.04)' }}
    >
      <span className="text-xs" style={{ color: '#6b7280' }}>{label}</span>
      <div className="flex items-center gap-2">
        <a
          href={`https://basescan.org/address/${address}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs font-mono hover:underline"
          style={{ color: '#e5e7eb' }}
        >
          {shortenAddress(address)}
        </a>
        <button
          onClick={copy}
          className="text-xs px-1.5 py-0.5 rounded transition-all"
          style={{
            background: copied ? 'rgba(16,185,129,0.15)' : 'rgba(255,255,255,0.06)',
            color: copied ? '#34d399' : '#9ca3af',
            border: copied ? '1px solid rgba(16,185,129,0.3)' : '1px solid rgba(255,255,255,0.08)',
            minWidth: 38,
          }}
        >
          {copied ? '✓' : 'copy'}
        </button>
      </div>
    </div>
  )
}

interface Props {
  tokenAddress: string
  creator: string
  uniswapPair: string | null
}

export function TokenInfoPanel({ tokenAddress, creator, uniswapPair }: Props) {
  const { data: bcPairRaw } = useReadContract({
    address: ADDRESSES.GradPadFactory,
    abi: ABIS.GradPadFactory,
    functionName: 'tokenToPair',
    args: [tokenAddress as `0x${string}`],
  })

  const bcPair = bcPairRaw as string | undefined
  const ZERO = '0x0000000000000000000000000000000000000000'

  return (
    <div
      className="rounded-2xl p-5"
      style={{
        background: 'rgba(255,255,255,0.025)',
        border: '1px solid rgba(255,255,255,0.07)',
      }}
    >
      <h2 className="text-base font-bold text-white mb-1">Contract Info</h2>
      <div>
        <CopyableRow label="Token" address={tokenAddress} />
        <CopyableRow label="Creator" address={creator} />
        {bcPair && bcPair !== ZERO && (
          <CopyableRow label="Bonding Pair" address={bcPair} />
        )}
        {uniswapPair && uniswapPair !== ZERO && (
          <CopyableRow label="Uniswap Pair" address={uniswapPair} />
        )}
        <CopyableRow label="Factory" address={ADDRESSES.GradPadFactory} />
      </div>
    </div>
  )
}
