export type Phase = 'bonding' | 'uniswap'

export interface Bucket {
  id: string
  index: number
  name: string
  basisPoints: number       // out of 10000
  recipient: string
  cliff: number             // seconds
  vestingDuration: number   // seconds (0 = instant)
  isLiquidity: boolean
  totalClaimed: string      // decimal string
}

export interface GradPadToken {
  id: string                // contract address
  name: string
  symbol: string
  creator: string
  createdAt: string
  bondingPhase: boolean
  graduatedAt: string | null
  uniswapPair: string | null
  totalVolume: string
  tradeCount: string
  buckets: Bucket[]
  trades?: Trade[]
}

export interface Trade {
  id: string
  trader: string
  isBuy: boolean
  amountIn: string
  amountOut: string
  price: string
  timestamp: string
  phase: Phase
}

export interface BucketFormInput {
  name: string
  basisPoints: number
  recipient: string
  cliff: number
  vestingDuration: number
  isLiquidity: boolean
}
