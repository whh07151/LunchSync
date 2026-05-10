interface Props {
  message: string;
  hint?: string;
}

export default function EmptyState({ message, hint }: Props) {
  return (
    <div className="text-center py-12 text-ink-500">
      <div className="inline-flex h-10 w-10 rounded-full bg-gray-100 items-center justify-center mb-2 text-ink-500">
        <svg
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <circle cx="12" cy="12" r="10" />
          <path d="M8 12h8" />
        </svg>
      </div>
      <p className="text-sm">{message}</p>
      {hint && <p className="text-xs mt-1 text-ink-500/80">{hint}</p>}
    </div>
  );
}
