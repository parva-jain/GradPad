import { BigDecimal } from '@graphprotocol/graph-ts'
import { BucketClaimed } from '../generated/templates/GradPadToken/GradPadToken'
import { Bucket, BucketClaim } from '../generated/schema'

const DECIMALS = BigDecimal.fromString('1000000000000000000')

export function handleBucketClaimed(event: BucketClaimed): void {
  let tokenAddress = event.address.toHex()
  let bucketId = tokenAddress + '-' + event.params.bucketIndex.toString()
  let bucket = Bucket.load(bucketId)
  if (!bucket) return

  let amount = event.params.amount.toBigDecimal().div(DECIMALS)

  let claimId = event.transaction.hash.toHex() + '-' + event.params.bucketIndex.toString()
  let claim = new BucketClaim(claimId)
  claim.bucket = bucketId
  claim.recipient = event.params.recipient
  claim.amount = amount
  claim.timestamp = event.block.timestamp
  claim.save()

  bucket.totalClaimed = bucket.totalClaimed.plus(amount)
  bucket.save()
}
