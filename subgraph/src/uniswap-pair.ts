import { BigDecimal, BigInt, dataSource } from '@graphprotocol/graph-ts'
import { Swap } from '../generated/templates/UniswapV2Pair/UniswapV2Pair'
import { GradPadToken, Trade } from '../generated/schema'

const TOKEN_DECIMALS = BigDecimal.fromString('1000000000000000000') // 1e18 — GradPad tokens
const ASSET_DECIMALS = BigDecimal.fromString('1000000')             // 1e6  — MockUSDC

function toTokenDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal().div(TOKEN_DECIMALS)
}

function toAssetDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal().div(ASSET_DECIMALS)
}

export function handleSwap(event: Swap): void {
  let context = dataSource.context()
  let tokenAddress = context.getString('token')
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  // gradpadIsToken0 was stored at graduation time by comparing addresses.
  // If true:  token0 = GradPad (18 dec), token1 = USDC (6 dec)
  // If false: token0 = USDC (6 dec),     token1 = GradPad (18 dec)
  let gradpadIsToken0 = context.getBoolean('gradpadIsToken0')

  let gradpadAmount0In  = toTokenDecimal(event.params.amount0In)
  let gradpadAmount0Out = toTokenDecimal(event.params.amount0Out)
  let gradpadAmount1In  = toTokenDecimal(event.params.amount1In)
  let gradpadAmount1Out = toTokenDecimal(event.params.amount1Out)

  let usdcAmount0In  = toAssetDecimal(event.params.amount0In)
  let usdcAmount0Out = toAssetDecimal(event.params.amount0Out)
  let usdcAmount1In  = toAssetDecimal(event.params.amount1In)
  let usdcAmount1Out = toAssetDecimal(event.params.amount1Out)

  let zero = BigDecimal.fromString('0')

  // Determine buy vs sell and extract the correct amounts with correct decimals.
  // Buy  = USDC flowing in, GradPad flowing out
  // Sell = GradPad flowing in, USDC flowing out
  let isBuy: boolean
  let usdcAmount: BigDecimal
  let gpAmount: BigDecimal
  let amountIn: BigDecimal
  let amountOut: BigDecimal

  if (gradpadIsToken0) {
    // token0 = GradPad, token1 = USDC
    // Buy:  amount1In > 0 (USDC in) and amount0Out > 0 (GradPad out)
    // Sell: amount0In > 0 (GradPad in) and amount1Out > 0 (USDC out)
    isBuy = usdcAmount1In.gt(zero)
    usdcAmount = isBuy ? usdcAmount1In  : usdcAmount1Out
    gpAmount   = isBuy ? gradpadAmount0Out : gradpadAmount0In
    amountIn   = isBuy ? usdcAmount1In  : gradpadAmount0In
    amountOut  = isBuy ? gradpadAmount0Out : usdcAmount1Out
  } else {
    // token0 = USDC, token1 = GradPad
    // Buy:  amount0In > 0 (USDC in) and amount1Out > 0 (GradPad out)
    // Sell: amount1In > 0 (GradPad in) and amount0Out > 0 (USDC out)
    isBuy = usdcAmount0In.gt(zero)
    usdcAmount = isBuy ? usdcAmount0In  : usdcAmount0Out
    gpAmount   = isBuy ? gradpadAmount1Out : gradpadAmount1In
    amountIn   = isBuy ? usdcAmount0In  : gradpadAmount1In
    amountOut  = isBuy ? gradpadAmount1Out : usdcAmount0Out
  }

  let price = gpAmount.gt(zero) ? usdcAmount.div(gpAmount) : zero

  let tradeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let trade = new Trade(tradeId)
  trade.token = tokenAddress
  trade.trader = event.params.to
  trade.isBuy = isBuy
  trade.amountIn = amountIn
  trade.amountOut = amountOut
  trade.price = price
  trade.timestamp = event.block.timestamp
  trade.blockNumber = event.block.number
  trade.phase = 'uniswap'
  trade.save()

  token.totalVolume = token.totalVolume.plus(usdcAmount)
  token.tradeCount = token.tradeCount.plus(BigInt.fromI32(1))
  token.save()
}
