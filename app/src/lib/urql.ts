import { createClient, cacheExchange, fetchExchange } from 'urql'

export const urqlClient = createClient({
  url: process.env.NEXT_PUBLIC_SUBGRAPH_URL!,
  exchanges: [cacheExchange, fetchExchange],
})
