import { createClient, cacheExchange, fetchExchange } from 'urql'

const SUBGRAPH_URL =
  process.env.NEXT_PUBLIC_SUBGRAPH_URL ??
  'https://api.studio.thegraph.com/query/50551/gradpad/v0.0.2'

export const urqlClient = createClient({
  url: SUBGRAPH_URL,
  exchanges: [cacheExchange, fetchExchange],
  preferGetMethod: false,
})
