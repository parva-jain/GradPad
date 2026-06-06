import { BucketFormInput } from '@/types'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { X } from 'lucide-react'

const BUCKET_NAMES = ['Team', 'Treasury', 'Community', 'Growth', 'Advisor', 'Reserve', 'Liquidity', 'Custom']
const CLIFF_OPTIONS = [
  { label: 'None', value: 0 },
  { label: '30 days', value: 30 * 86400 },
  { label: '90 days', value: 90 * 86400 },
  { label: '6 months', value: 180 * 86400 },
  { label: '1 year', value: 365 * 86400 },
]
const VEST_OPTIONS = [
  { label: 'Instant', value: 0 },
  { label: '6 months', value: 180 * 86400 },
  { label: '1 year', value: 365 * 86400 },
  { label: '2 years', value: 730 * 86400 },
  { label: '4 years', value: 1460 * 86400 },
]

interface Props {
  bucket: BucketFormInput
  index: number
  onChange: (index: number, updated: Partial<BucketFormInput>) => void
  onRemove: (index: number) => void
  canRemove: boolean
}

export function BucketRow({ bucket, index, onChange, onRemove, canRemove }: Props) {
  return (
    <div className="grid gap-2 items-center" style={{ gridTemplateColumns: '3fr 1fr 3fr 2fr 2fr auto' }}>
      {/* Name */}
      <Select value={bucket.name} onValueChange={v => { if (v) onChange(index, { name: v }) }}>
        <SelectTrigger style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {BUCKET_NAMES.map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}
        </SelectContent>
      </Select>
      {/* Percent */}
      <Input
        type="number" min={0} max={100}
        value={bucket.basisPoints / 100}
        onChange={e => onChange(index, { basisPoints: Math.round(parseFloat(e.target.value || '0') * 100) })}
        style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
        placeholder="%"
      />
      {/* Recipient */}
      <Input
        value={bucket.isLiquidity ? '— (contract)' : bucket.recipient}
        onChange={e => onChange(index, { recipient: e.target.value })}
        disabled={bucket.isLiquidity}
        placeholder="0x..."
        className="font-mono text-xs"
        style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
      />
      {/* Cliff */}
      <Select
        value={bucket.cliff.toString()}
        onValueChange={v => { if (v) onChange(index, { cliff: parseInt(v) }) }}
        disabled={bucket.isLiquidity}
      >
        <SelectTrigger style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {CLIFF_OPTIONS.map(o => <SelectItem key={o.value} value={o.value.toString()}>{o.label}</SelectItem>)}
        </SelectContent>
      </Select>
      {/* Vesting */}
      <Select
        value={bucket.vestingDuration.toString()}
        onValueChange={v => { if (v) onChange(index, { vestingDuration: parseInt(v) }) }}
        disabled={bucket.isLiquidity}
      >
        <SelectTrigger style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {VEST_OPTIONS.map(o => <SelectItem key={o.value} value={o.value.toString()}>{o.label}</SelectItem>)}
        </SelectContent>
      </Select>
      {/* Remove */}
      <div className="flex justify-center">
        {canRemove ? (
          <Button variant="ghost" size="icon" onClick={() => onRemove(index)}
            className="h-7 w-7 text-muted-foreground hover:text-red-400">
            <X className="h-4 w-4" />
          </Button>
        ) : <div className="h-7 w-7" />}
      </div>
    </div>
  )
}
