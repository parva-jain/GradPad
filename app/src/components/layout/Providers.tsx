'use client'

import { useState } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { WagmiProvider } from 'wagmi'
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit'
import { Provider as UrqlProvider } from 'urql'
import { wagmiConfig } from '@/lib/wagmi'
import { urqlClient } from '@/lib/urql'
import '@rainbow-me/rainbowkit/styles.css'

const rainbowDarkTheme = darkTheme()

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient())

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={rainbowDarkTheme}>
          <UrqlProvider value={urqlClient}>
            {children}
          </UrqlProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  )
}
