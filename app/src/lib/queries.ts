export const TOKENS_QUERY = `
  query Tokens($first: Int!, $orderBy: String!, $orderDirection: String!) {
    gradPadTokens(
      first: $first
      orderBy: $orderBy
      orderDirection: $orderDirection
    ) {
      id name symbol bondingPhase createdAt totalVolume tradeCount
      buckets { name basisPoints isLiquidity }
    }
  }
`

export const TOKEN_DETAIL_QUERY = `
  query TokenDetail($address: ID!) {
    gradPadToken(id: $address) {
      id name symbol creator bondingPhase createdAt graduatedAt uniswapPair
      totalVolume tradeCount
      buckets {
        id index name basisPoints recipient cliff vestingDuration isLiquidity totalClaimed
      }
      trades(first: 200, orderBy: timestamp, orderDirection: asc) {
        id isBuy amountIn amountOut price timestamp phase
      }
    }
  }
`

export const USER_TOKENS_QUERY = `
  query UserTokens($creator: Bytes!) {
    gradPadTokens(where: { creator: $creator }) {
      id name symbol bondingPhase totalVolume tradeCount
    }
  }
`

export const USER_TRADES_QUERY = `
  query UserTrades($trader: Bytes!) {
    trades(where: { trader: $trader }, orderBy: timestamp, orderDirection: desc, first: 50) {
      id token { id name symbol } isBuy amountIn amountOut price timestamp phase
    }
  }
`
