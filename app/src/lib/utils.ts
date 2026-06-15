import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import type { CombinedError } from 'urql'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

export function formatDecimal(value: string, decimals = 2): string {
  const num = parseFloat(value)
  if (isNaN(num)) return '0'
  if (num >= 1_000_000) return `${(num / 1_000_000).toFixed(decimals)}M`
  if (num >= 1_000) return `${(num / 1_000).toFixed(decimals)}K`
  return num.toFixed(decimals)
}

export function secondsToDuration(seconds: number): string {
  if (seconds === 0) return 'None'
  const days = Math.floor(seconds / 86400)
  return `${days} day${days !== 1 ? 's' : ''}`
}

export function basisPointsToPercent(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`
}

export function formatUrqlError(error: CombinedError): string {
  const msg = error.message
  if (msg.includes('<!DOCTYPE') || msg.includes('<html')) {
    return 'Unable to reach the subgraph — the endpoint may be misconfigured or temporarily down.'
  }
  if (msg.startsWith('[Network]')) {
    return 'Network error: unable to connect to the data source. Check your internet connection.'
  }
  if (error.graphQLErrors.length > 0) {
    return error.graphQLErrors[0].message
  }
  return 'Something went wrong. Please try again.'
}
