function Skeleton({ className, style }: { className?: string; style?: React.CSSProperties }) {
  return (
    <div
      className={`animate-pulse rounded-xl ${className ?? ''}`}
      style={{ background: 'rgba(255,255,255,0.05)', ...style }}
    />
  )
}

export default function TokenLoading() {
  return (
    <main className="max-w-7xl mx-auto px-4 py-8" style={{ minHeight: '100vh' }}>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

        {/* Left column */}
        <div className="lg:col-span-2 space-y-6">
          {/* Header */}
          <div className="space-y-2">
            <Skeleton style={{ height: 32, width: 200 }} />
            <Skeleton style={{ height: 16, width: 80 }} />
            <Skeleton style={{ height: 40, width: 160, marginTop: 8 }} />
          </div>

          {/* Chart */}
          <Skeleton style={{ height: 260 }} />

          {/* Progress bar */}
          <Skeleton style={{ height: 40 }} />

          {/* Stats grid */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} style={{ height: 64 }} />
            ))}
          </div>

          {/* Contract info */}
          <Skeleton style={{ height: 160 }} />

          {/* Allocation */}
          <Skeleton style={{ height: 320 }} />
        </div>

        {/* Right column */}
        <div className="lg:col-span-1 space-y-4">
          <Skeleton style={{ height: 320 }} />
          <Skeleton style={{ height: 200 }} />
        </div>
      </div>
    </main>
  )
}
