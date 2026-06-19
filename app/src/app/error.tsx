'use client'

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  return (
    <main
      className="flex flex-col items-center justify-center min-h-screen gap-6"
      style={{ background: '#0c0a06' }}
    >
      <div className="text-center space-y-2">
        <h1 className="text-xl font-bold text-white">Something went wrong</h1>
        <p className="text-sm max-w-sm" style={{ color: '#6b7280' }}>
          {error.message || 'An unexpected error occurred.'}
        </p>
      </div>
      <button
        onClick={reset}
        className="px-5 py-2.5 rounded-xl text-sm font-semibold"
        style={{
          background: 'rgba(251,191,36,0.1)',
          border: '1px solid rgba(251,191,36,0.2)',
          color: '#fbbf24',
        }}
      >
        Try again
      </button>
    </main>
  )
}
