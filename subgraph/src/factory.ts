import { BigDecimal, BigInt, DataSourceContext } from '@graphprotocol/graph-ts'
import {
  GPTokenCreated,
  BucketAdded,
  GPTokenGraduated,
  GPTokenBought,
  GPTokenSold,
  FeeCollected,
} from '../generated/GradPadFactory/GradPadFactory'
import { GradPadToken, Bucket, Trade, User, FeeEvent } from '../generated/schema'
import { UniswapV2Pair, GradPadToken as GradPadTokenTemplate } from '../generated/templates'

const TOKEN_DECIMALS = BigDecimal.fromString('1000000000000000000') // 1e18 — GradPad tokens
const ASSET_DECIMALS = BigDecimal.fromString('1000000')             // 1e6  — MockUSDC

function toTokenDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal().div(TOKEN_DECIMALS)
}

function toAssetDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal().div(ASSET_DECIMALS)
}

function loadOrCreateUser(address: string): User {
  let user = User.load(address)
  if (!user) {
    user = new User(address)
    user.tradeCount = BigInt.fromI32(0)
    user.totalVolumeUSDC = BigDecimal.fromString('0')
  }
  return user
}

export function handleGPTokenCreated(event: GPTokenCreated): void {
  let token = new GradPadToken(event.params.token.toHex())
  token.name = event.params.name
  token.symbol = event.params.symbol
  token.creator = event.params.creator
  token.createdAt = event.block.timestamp
  token.bondingPhase = true
  token.totalVolume = BigDecimal.fromString('0')
  token.totalFeesCollected = BigDecimal.fromString('0')
  token.tradeCount = BigInt.fromI32(0)
  token.save()

  // Start indexing BucketClaimed events from this clone
  GradPadTokenTemplate.create(event.params.token)
}

export function handleBucketAdded(event: BucketAdded): void {
  let id = event.params.token.toHex() + '-' + event.params.bucketIndex.toString()
  let bucket = new Bucket(id)
  bucket.token = event.params.token.toHex()
  bucket.index = event.params.bucketIndex
  bucket.name = event.params.name
  bucket.basisPoints = event.params.basisPoints
  bucket.recipient = event.params.recipient
  bucket.cliff = event.params.cliff
  bucket.vestingDuration = event.params.vestingDuration
  bucket.isLiquidity = event.params.isLiquidity
  bucket.totalClaimed = BigDecimal.fromString('0')
  bucket.save()
}

export function handleGPTokenGraduated(event: GPTokenGraduated): void {
  let token = GradPadToken.load(event.params.token.toHex())
  if (!token) return

  token.bondingPhase = false
  token.graduatedAt = event.block.timestamp
  token.uniswapPair = event.params.uniswapPair
  token.save()

  // Spin up a dynamic data source to index Uniswap pair Swap events.
  // Store token address and slot ordering so uniswap-pair.ts applies the right decimals.
  // Uniswap V2 sorts tokens by address: lower address = token0.
  // Hex string comparison is equivalent to numeric address comparison (same length, lowercase).
  let context = new DataSourceContext()
  context.setString('token', event.params.token.toHex())
  context.setBoolean('gradpadIsToken0', event.params.token.toHex() < '0x7b851635eea924e8501e733909fcf91ab1b98348')
  UniswapV2Pair.createWithContext(event.params.uniswapPair, context)
}

export function handleGPTokenBought(event: GPTokenBought): void {
  let tokenAddress = event.params.token.toHex()
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  let amountInDecimal  = toAssetDecimal(event.params.assetIn)    // USDC spent (6 decimals)
  let amountOutDecimal = toTokenDecimal(event.params.tokensOut)  // tokens received (18 decimals)
  let price = amountOutDecimal.gt(BigDecimal.fromString('0'))
    ? amountInDecimal.div(amountOutDecimal)
    : BigDecimal.fromString('0')

  let tradeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let trade = new Trade(tradeId)
  trade.token = tokenAddress
  trade.trader = event.params.buyer
  trade.isBuy = true
  trade.amountIn = amountInDecimal
  trade.amountOut = amountOutDecimal
  trade.price = price
  trade.timestamp = event.block.timestamp
  trade.blockNumber = event.block.number
  trade.phase = 'bonding'
  trade.save()

  token.totalVolume = token.totalVolume.plus(amountInDecimal)
  token.tradeCount = token.tradeCount.plus(BigInt.fromI32(1))
  token.save()

  let user = loadOrCreateUser(event.params.buyer.toHex())
  user.tradeCount = user.tradeCount.plus(BigInt.fromI32(1))
  user.totalVolumeUSDC = user.totalVolumeUSDC.plus(amountInDecimal)
  user.save()
}

export function handleGPTokenSold(event: GPTokenSold): void {
  let tokenAddress = event.params.token.toHex()
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  let amountInDecimal  = toTokenDecimal(event.params.tokensIn)  // tokens sold (18 decimals)
  let amountOutDecimal = toAssetDecimal(event.params.assetOut)  // USDC received (6 decimals)
  let price = amountInDecimal.gt(BigDecimal.fromString('0'))
    ? amountOutDecimal.div(amountInDecimal)
    : BigDecimal.fromString('0')

  let tradeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let trade = new Trade(tradeId)
  trade.token = tokenAddress
  trade.trader = event.params.seller
  trade.isBuy = false
  trade.amountIn = amountInDecimal
  trade.amountOut = amountOutDecimal
  trade.price = price
  trade.timestamp = event.block.timestamp
  trade.blockNumber = event.block.number
  trade.phase = 'bonding'
  trade.save()

  token.totalVolume = token.totalVolume.plus(amountOutDecimal)
  token.tradeCount = token.tradeCount.plus(BigInt.fromI32(1))
  token.save()

  let user = loadOrCreateUser(event.params.seller.toHex())
  user.tradeCount = user.tradeCount.plus(BigInt.fromI32(1))
  user.totalVolumeUSDC = user.totalVolumeUSDC.plus(amountOutDecimal)
  user.save()
}

export function handleFeeCollected(event: FeeCollected): void {
  let tokenAddress = event.params.token.toHex()
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  let feeDecimal = toAssetDecimal(event.params.feeAmount) // USDC fee (6 decimals)

  let feeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let fee = new FeeEvent(feeId)
  fee.token = tokenAddress
  fee.buyer = event.params.buyer
  fee.feeAmount = feeDecimal
  fee.timestamp = event.block.timestamp
  fee.blockNumber = event.block.number
  fee.save()

  token.totalFeesCollected = token.totalFeesCollected.plus(feeDecimal)
  token.save()
}
