import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, ExternalLink, AlertCircle } from 'lucide-react';
import { TagChip } from './TagChip';

interface Source {
  id: string;
  siteIcon: string;
  siteName: string;
  title: string;
  snippet: string;
  url: string;
}

interface EvidenceSheetProps {
  isOpen: boolean;
  onClose: () => void;
  achievement: {
    achievement: string;
    category: string;
    confidence: 'high' | 'medium' | 'low';
    datePrecision: 'exact' | 'year';
  };
  sources?: Source[];
  isLoading?: boolean;
  onReportIssue?: () => void;
}

const confidenceConfig = {
  high: {
    label: 'High Confidence',
    bg: 'bg-[#4ADE80]/10',
    text: 'text-[#4ADE80]',
    border: 'border-[#4ADE80]/30',
    icon: '✓',
  },
  medium: {
    label: 'Medium Confidence',
    bg: 'bg-[#FBBF24]/10',
    text: 'text-[#FBBF24]',
    border: 'border-[#FBBF24]/30',
    icon: '~',
  },
  low: {
    label: 'Low Confidence',
    bg: 'bg-[#F87171]/10',
    text: 'text-[#F87171]',
    border: 'border-[#F87171]/30',
    icon: '!',
  },
};

const datePrecisionConfig = {
  exact: {
    label: 'Exact Date',
    icon: '📅',
  },
  year: {
    label: 'Year Only',
    icon: '📆',
  },
};

// Mock sources for demo
const defaultSources: Source[] = [
  {
    id: '1',
    siteIcon: '🌐',
    siteName: 'Wikipedia',
    title: 'Elon Musk - Early Career',
    snippet: 'In 1999, Musk co-founded X.com, an online financial services and e-mail payment company. The startup was one of the first online banks...',
    url: 'https://en.wikipedia.org/wiki/Elon_Musk',
  },
  {
    id: '2',
    siteIcon: '📰',
    siteName: 'Business Insider',
    title: 'How Elon Musk Made His Fortune',
    snippet: 'Musk received $22 million from the sale of Zip2, which he used to co-found X.com. The company later merged with Confinity to become PayPal.',
    url: 'https://businessinsider.com/elon-musk-fortune',
  },
  {
    id: '3',
    siteIcon: '📚',
    siteName: 'Biography.com',
    title: 'Elon Musk Biography',
    snippet: 'X.com eventually merged with Confinity in 2000, and the merged company became known as PayPal. Musk served as CEO until October 2000.',
    url: 'https://biography.com/elon-musk',
  },
];

// Skeleton loader component
function SourceSkeleton({ index }: { index: number }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.1, duration: 0.4 }}
      className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
    >
      <div className="flex items-start gap-3">
        {/* Site Icon Skeleton */}
        <div className="w-12 h-12 rounded-[12px] bg-[#2A2A2E] animate-pulse flex-shrink-0" />

        {/* Content Skeleton */}
        <div className="flex-1 space-y-2">
          {/* Site name skeleton */}
          <div className="h-3 w-24 bg-[#2A2A2E] rounded-full animate-pulse" />
          
          {/* Title skeleton */}
          <div className="h-4 w-full bg-[#2A2A2E] rounded-full animate-pulse" />
          <div className="h-4 w-3/4 bg-[#2A2A2E] rounded-full animate-pulse" />
          
          {/* Snippet skeleton */}
          <div className="space-y-1.5 pt-1">
            <div className="h-3 w-full bg-[#2A2A2E] rounded-full animate-pulse" />
            <div className="h-3 w-5/6 bg-[#2A2A2E] rounded-full animate-pulse" />
          </div>
        </div>

        {/* Button Skeleton */}
        <div className="w-16 h-9 rounded-[12px] bg-[#2A2A2E] animate-pulse flex-shrink-0" />
      </div>
    </motion.div>
  );
}

export function EvidenceSheet({
  isOpen,
  onClose,
  achievement,
  sources = defaultSources,
  isLoading = false,
  onReportIssue,
}: EvidenceSheetProps) {
  const confidenceStyle = confidenceConfig[achievement.confidence];
  const precisionInfo = datePrecisionConfig[achievement.datePrecision];

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm z-40"
          />

          {/* Bottom Sheet */}
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 30, stiffness: 300 }}
            className="fixed bottom-0 left-0 right-0 bg-[#121212] rounded-t-[24px] border-t border-[#2A2A2E] z-50 max-h-[85vh] flex flex-col"
          >
            {/* Handle */}
            <div className="flex justify-center pt-3 pb-2">
              <div className="w-12 h-1 bg-[#2A2A2E] rounded-full" />
            </div>

            {/* Header */}
            <div className="px-6 pt-4 pb-5 border-b border-[#2A2A2E]">
              {/* Title Row */}
              <div className="flex items-start justify-between gap-3 mb-4">
                <div className="flex-1">
                  <h2 className="text-white text-xl mb-2 leading-snug">{achievement.achievement}</h2>
                  <TagChip label={achievement.category} variant="category" className="text-xs px-3 py-1" />
                </div>
                <motion.button
                  whileHover={{ scale: 1.1, rotate: 90 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={onClose}
                  className="w-10 h-10 rounded-full bg-[#1C1C1E] border border-[#2A2A2E] flex items-center justify-center flex-shrink-0"
                >
                  <X className="w-5 h-5 text-[#A1A1AA]" />
                </motion.button>
              </div>

              {/* Metadata Row */}
              <div className="flex items-center gap-2 flex-wrap">
                {/* Confidence Badge */}
                <div
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full border ${confidenceStyle.bg} ${confidenceStyle.text} ${confidenceStyle.border}`}
                >
                  <span className="text-sm">{confidenceStyle.icon}</span>
                  <span className="text-xs font-medium">{confidenceStyle.label}</span>
                </div>

                {/* Date Precision Label */}
                <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-[#2A2A2E] bg-[#1C1C1E]">
                  <span className="text-sm">{precisionInfo.icon}</span>
                  <span className="text-xs text-[#A1A1AA] font-medium">{precisionInfo.label}</span>
                </div>
              </div>
            </div>

            {/* Content */}
            <div className="flex-1 overflow-y-auto px-6 py-6">
              {/* Sources Header */}
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-white font-medium">
                  {isLoading ? 'Loading sources...' : `${sources.length} Sources`}
                </h3>
                {!isLoading && (
                  <span className="text-[#A1A1AA] text-xs">Verified references</span>
                )}
              </div>

              {/* Source List */}
              <div className="space-y-3">
                {isLoading ? (
                  // Loading Skeletons
                  <>
                    <SourceSkeleton index={0} />
                    <SourceSkeleton index={1} />
                    <SourceSkeleton index={2} />
                  </>
                ) : (
                  // Actual Sources
                  sources.map((source, index) => (
                    <motion.div
                      key={source.id}
                      initial={{ opacity: 0, y: 20 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: index * 0.1, duration: 0.4 }}
                      className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all"
                    >
                      <div className="flex items-start gap-3">
                        {/* Site Icon */}
                        <div className="w-12 h-12 rounded-[12px] bg-gradient-to-br from-[#7B61FF]/20 to-[#A78BFA]/20 border border-[#7B61FF]/30 flex items-center justify-center flex-shrink-0 text-2xl">
                          {source.siteIcon}
                        </div>

                        {/* Content */}
                        <div className="flex-1 min-w-0">
                          {/* Site Name */}
                          <div className="flex items-center gap-2 mb-1">
                            <span className="text-[#7B61FF] text-xs font-medium">
                              {source.siteName}
                            </span>
                            <div className="w-1 h-1 rounded-full bg-[#2A2A2E]" />
                            <span className="text-[#A1A1AA] text-xs">Verified</span>
                          </div>

                          {/* Title */}
                          <h4 className="text-white text-sm font-medium mb-2 leading-snug">
                            {source.title}
                          </h4>

                          {/* Snippet */}
                          <p className="text-[#A1A1AA] text-xs leading-relaxed line-clamp-2">
                            {source.snippet}
                          </p>
                        </div>

                        {/* Open Button */}
                        <motion.button
                          whileHover={{ scale: 1.05 }}
                          whileTap={{ scale: 0.95 }}
                          onClick={() => window.open(source.url, '_blank')}
                          className="px-3 py-2 rounded-[12px] bg-[#7B61FF] text-white text-xs font-medium flex items-center gap-1 flex-shrink-0 shadow-lg shadow-[#7B61FF]/20"
                        >
                          Open
                          <ExternalLink className="w-3 h-3" />
                        </motion.button>
                      </div>
                    </motion.div>
                  ))
                )}
              </div>

              {/* Report Issue Link */}
              {!isLoading && (
                <motion.button
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.5 }}
                  whileHover={{ x: 4 }}
                  onClick={onReportIssue}
                  className="w-full mt-6 p-4 rounded-[20px] bg-[#1C1C1E] border border-[#2A2A2E] flex items-center justify-center gap-2 hover:border-[#F87171]/30 transition-all"
                >
                  <AlertCircle className="w-4 h-4 text-[#F87171]" />
                  <span className="text-[#A1A1AA] text-sm">Report an issue with this evidence</span>
                </motion.button>
              )}

              {/* Bottom Padding */}
              <div className="h-6" />
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}