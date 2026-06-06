import { GradPadToken } from '@/types'
import { TokenCard } from './TokenCard'

interface Props {
  tokens: GradPadToken[]
}

export function TokenGrid({ tokens }: Props) {
  if (tokens.length === 0) {
    return (
      <div className="text-center py-24 text-muted-foreground">
        No tokens found.
      </div>
    )
  }
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      {tokens.map(t => <TokenCard key={t.id} token={t} />)}
    </div>
  )
}
