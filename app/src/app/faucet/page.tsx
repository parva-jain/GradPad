'use client'

import { useEffect, useState } from 'react'
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { parseUnits, formatUnits } from 'viem'
import { Button } from '@/components/ui/button'

const DAILY_LIMIT = parseUnits('1000', 6)
const ZERO = BigInt(0)

export default function FaucetPage() {
  const { address, isConnected } = useAccount()
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>(undefined)

  const { data: mintedToday, refetch: refetchMinted } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ABIS.MockUSDC,
    functionName: 'mintedToday',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: balance, refetch: refetchBalance } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ABIS.MockUSDC,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { writeContractAsync, isPending } = useWriteContract()

  const { data: receipt } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: !!txHash },
  })

  const isConfirming = !!txHash && !receipt

  useEffect(() => {
    if (receipt) {
      refetchMinted()
      refetchBalance()
    }
  }, [receipt, refetchMinted, refetchBalance])

  const mintedTodayBigInt = typeof mintedToday === 'bigint' ? mintedToday : ZERO
  const balanceBigInt = typeof balance === 'bigint' ? balance : ZERO
  const remainingToday = mintedTodayBigInt < DAILY_LIMIT ? DAILY_LIMIT - mintedTodayBigInt : ZERO

  const mintedPct = Number((mintedTodayBigInt * BigInt(100)) / DAILY_LIMIT)
  const remainingDisplay = formatUnits(remainingToday, 6).split('.')[0]
  const mintedDisplay = formatUnits(mintedTodayBigInt, 6).split('.')[0]
  const balanceDisplay = parseFloat(formatUnits(balanceBigInt, 6)).toFixed(2)

  async function handleMint() {
    if (!address) return
    try {
      const hash = await writeContractAsync({
        address: ADDRESSES.MockUSDC,
        abi: ABIS.MockUSDC,
        functionName: 'mint',
        args: [parseUnits('1000', 6)],
      })
      setTxHash(hash)
    } catch (err) {
      console.error('Mint failed:', err)
    }
  }

  const isLimitReached = remainingToday === ZERO

  return (
    <main
      className="flex items-center justify-center min-h-screen px-4"
      style={{ background: '#0c0a06' }}
    >
      <div
        className="w-full max-w-sm rounded-2xl p-6 space-y-5"
        style={{
          background: 'rgba(255,255,255,0.025)',
          border: '1px solid rgba(255,255,255,0.07)',
        }}
      >
        <div>
          <h1 className="text-xl font-extrabold text-white">Mock USDC Faucet</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Mint up to 1,000 mUSDC per day to trade on GradPad (Base mainnet).
          </p>
        </div>

        {!isConnected ? (
          <ConnectButton />
        ) : (
          <>
            <div
              className="rounded-xl p-4 space-y-2"
              style={{
                background: 'rgba(255,255,255,0.03)',
                border: '1px solid rgba(251,191,36,0.1)',
              }}
            >
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Your balance</span>
                <span className="font-bold text-white">{balanceDisplay} mUSDC</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Remaining today</span>
                <span className="font-bold text-white">{remainingDisplay} mUSDC</span>
              </div>
              <div>
                <div
                  className="h-1.5 w-full rounded-full mt-2"
                  style={{ background: 'rgba(255,255,255,0.06)' }}
                >
                  <div
                    className="h-full rounded-full transition-all"
                    style={{
                      width: `${mintedPct}%`,
                      background: 'linear-gradient(90deg, #d97706, #fbbf24)',
                    }}
                  />
                </div>
                <div className="flex justify-between text-xs text-muted-foreground mt-1">
                  <span>Minted today</span>
                  <span>{mintedDisplay} / 1000 mUSDC</span>
                </div>
              </div>
            </div>

            <Button
              className="w-full font-bold"
              onClick={handleMint}
              disabled={isPending || isConfirming || isLimitReached}
              style={{
                background: isPending || isConfirming || isLimitReached
                  ? 'rgba(255,255,255,0.06)'
                  : 'linear-gradient(90deg, #d97706, #fbbf24)',
                color: isPending || isConfirming || isLimitReached ? '#6b7280' : '#0c0a06',
                border: 'none',
              }}
            >
              {isPending
                ? 'Confirm in wallet...'
                : isConfirming
                ? 'Confirming on-chain...'
                : isLimitReached
                ? 'Daily limit reached'
                : 'Mint 1000 mUSDC'}
            </Button>

            {isConfirming && (
              <p className="text-xs text-center text-muted-foreground">
                Waiting for the transaction to be included in a block...
              </p>
            )}
            {receipt && txHash && (
              <a
                href={`https://basescan.org/tx/${txHash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="block text-center text-xs hover:underline"
                style={{ color: '#34d399' }}
              >
                Minted — View on BaseScan ↗
              </a>
            )}
          </>
        )}
      </div>
    </main>
  )
}
