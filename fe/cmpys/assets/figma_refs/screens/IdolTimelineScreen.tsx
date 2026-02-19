import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { TimelineRow } from '../TimelineRow';
import { EvidenceSheet } from '../EvidenceSheet';
import { ChevronLeft } from 'lucide-react';

interface IdolTimelineScreenProps {
  onBack: () => void;
}

type FilterMode = 'exact' | 'upTo';

const achievements = [
  {
    age: 24,
    achievement: 'Founded Zip2',
    category: 'Entrepreneurship',
    description: 'Co-founded web software company',
    confidence: 'high' as const,
    datePrecision: 'year' as const,
  },
  {
    age: 28,
    achievement: 'Sold Zip2 for $307M',
    category: 'Finance',
    description: 'Received $22M from the sale',
    confidence: 'high' as const,
    datePrecision: 'exact' as const,
  },
  {
    age: 28,
    achievement: 'Co-founded X.com',
    category: 'Entrepreneurship',
    description: 'Online banking startup (later PayPal)',
    confidence: 'high' as const,
    datePrecision: 'year' as const,
  },
  {
    age: 30,
    achievement: 'X.com merged with Confinity',
    category: 'Business',
    description: 'Became CEO of merged company PayPal',
    confidence: 'medium' as const,
    datePrecision: 'year' as const,
  },
  {
    age: 31,
    achievement: 'PayPal sold to eBay for $1.5B',
    category: 'Finance',
    description: 'Received $165M from the sale',
    confidence: 'high' as const,
    datePrecision: 'exact' as const,
  },
  {
    age: 31,
    achievement: 'Founded SpaceX',
    category: 'Innovation',
    description: 'Aerospace manufacturer and space transport',
    confidence: 'high' as const,
    datePrecision: 'exact' as const,
  },
  {
    age: 32,
    achievement: 'Invested in Tesla Motors',
    category: 'Investment',
    description: 'Led Series A funding round',
    confidence: 'high' as const,
    datePrecision: 'year' as const,
  },
  {
    age: 33,
    achievement: 'Became Tesla Chairman',
    category: 'Leadership',
    description: 'Joined as chairman of the board',
    confidence: 'high' as const,
    datePrecision: 'exact' as const,
  },
  {
    age: 36,
    achievement: 'Tesla Roadster launched',
    category: 'Product',
    description: 'First highway-capable all-electric vehicle',
    confidence: 'medium' as const,
    datePrecision: 'year' as const,
  },
  {
    age: 38,
    achievement: 'Tesla IPO',
    category: 'Finance',
    description: 'Tesla went public on NASDAQ',
    confidence: 'high' as const,
    datePrecision: 'exact' as const,
  },
];

const userAge = 32; // Would come from user profile

export function IdolTimelineScreen({ onBack }: IdolTimelineScreenProps) {
  const [selectedEvidence, setSelectedEvidence] = useState<any>(null);
  const [filterMode, setFilterMode] = useState<FilterMode>('exact');
  const [evidenceSheetOpen, setEvidenceSheetOpen] = useState(false);
  const [selectedAchievement, setSelectedAchievement] = useState<any>(null);
  const [isLoadingEvidence, setIsLoadingEvidence] = useState(false);

  const handleOpenEvidence = (achievement: any) => {
    setSelectedAchievement(achievement);
    setEvidenceSheetOpen(true);
    setIsLoadingEvidence(true);
    // Simulate loading
    setTimeout(() => setIsLoadingEvidence(false), 1500);
  };

  const filteredAchievements = achievements.filter((a) => {
    if (filterMode === 'exact') {
      return a.age === userAge;
    } else {
      return a.age <= userAge;
    }
  });

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-6 border-b border-[#2A2A2E]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <div className="flex items-center gap-4 mb-6">
          <div className="w-12 h-12 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-lg shadow-[#7B61FF]/30">
            <span className="text-white font-medium">EM</span>
          </div>
          <div>
            <h1 className="text-white text-2xl">Elon Musk</h1>
            <p className="text-[#A1A1AA]">Timeline</p>
          </div>
        </div>
        
        {/* Context Text */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] px-4 py-3 border border-[#2A2A2E] mb-4"
        >
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-[#7B61FF]" />
              <span className="text-white text-sm">
                You are <span className="font-medium">{userAge}</span>
              </span>
            </div>
            <div className="w-px h-4 bg-[#2A2A2E]" />
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-[#A78BFA]" />
              <span className="text-[#A1A1AA] text-sm">
                Idol at <span className="text-white font-medium">{userAge}</span>
              </span>
            </div>
          </div>
        </motion.div>

        {/* Age Slider */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.4 }}
          className="space-y-3 mb-4"
        >
          <div className="flex justify-between items-center">
            <span className="text-[#A1A1AA] text-sm">Filter by age</span>
            <div className="flex items-center gap-2">
              <span className="text-[#7B61FF] text-xl font-medium">{userAge}</span>
              <span className="text-[#A1A1AA] text-sm">years</span>
            </div>
          </div>
          
          {/* Custom Slider */}
          <div className="relative">
            <input
              type="range"
              min={24}
              max={38}
              value={userAge}
              onChange={(e) => setSelectedEvidence(Number(e.target.value))}
              className="w-full h-2 bg-[#1C1C1E] rounded-full appearance-none cursor-pointer border border-[#2A2A2E]
                [&::-webkit-slider-thumb]:appearance-none
                [&::-webkit-slider-thumb]:w-6
                [&::-webkit-slider-thumb]:h-6
                [&::-webkit-slider-thumb]:rounded-full
                [&::-webkit-slider-thumb]:bg-gradient-to-br
                [&::-webkit-slider-thumb]:from-[#7B61FF]
                [&::-webkit-slider-thumb]:to-[#A78BFA]
                [&::-webkit-slider-thumb]:cursor-pointer
                [&::-webkit-slider-thumb]:shadow-lg
                [&::-webkit-slider-thumb]:shadow-[#7B61FF]/40
                [&::-webkit-slider-thumb]:border-2
                [&::-webkit-slider-thumb]:border-[#121212]
                [&::-moz-range-thumb]:appearance-none
                [&::-moz-range-thumb]:w-6
                [&::-moz-range-thumb]:h-6
                [&::-moz-range-thumb]:rounded-full
                [&::-moz-range-thumb]:bg-gradient-to-br
                [&::-moz-range-thumb]:from-[#7B61FF]
                [&::-moz-range-thumb]:to-[#A78BFA]
                [&::-moz-range-thumb]:cursor-pointer
                [&::-moz-range-thumb]:shadow-lg
                [&::-moz-range-thumb]:shadow-[#7B61FF]/40
                [&::-moz-range-thumb]:border-2
                [&::-moz-range-thumb]:border-[#121212]"
            />
            {/* Range Labels */}
            <div className="flex justify-between mt-2">
              <span className="text-[#A1A1AA] text-xs">24</span>
              <span className="text-[#A1A1AA] text-xs">38</span>
            </div>
          </div>
        </motion.div>

        {/* Segmented Control */}
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-1 border border-[#2A2A2E] flex gap-1"
        >
          <motion.button
            whileTap={{ scale: 0.98 }}
            onClick={() => setFilterMode('exact')}
            className={`flex-1 px-4 py-2.5 rounded-[16px] text-sm font-medium transition-all ${
              filterMode === 'exact'
                ? 'bg-[#7B61FF] text-white shadow-lg shadow-[#7B61FF]/30'
                : 'text-[#A1A1AA] hover:text-white'
            }`}
          >
            Exact age
          </motion.button>
          <motion.button
            whileTap={{ scale: 0.98 }}
            onClick={() => setFilterMode('upTo')}
            className={`flex-1 px-4 py-2.5 rounded-[16px] text-sm font-medium transition-all ${
              filterMode === 'upTo'
                ? 'bg-[#7B61FF] text-white shadow-lg shadow-[#7B61FF]/30'
                : 'text-[#A1A1AA] hover:text-white'
            }`}
          >
            Up to age
          </motion.button>
        </motion.div>
      </motion.div>

      {/* Results Count */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.4, duration: 0.4 }}
        className="px-6 py-3 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <div className="flex items-center justify-between">
          <p className="text-[#A1A1AA] text-sm">
            {filterMode === 'exact' ? (
              <>
                Showing <span className="text-white font-medium">{filteredAchievements.length}</span>{' '}
                {filteredAchievements.length === 1 ? 'achievement' : 'achievements'} at age{' '}
                <span className="text-[#7B61FF] font-medium">{userAge}</span>
              </>
            ) : (
              <>
                Showing <span className="text-white font-medium">{filteredAchievements.length}</span>{' '}
                {filteredAchievements.length === 1 ? 'achievement' : 'achievements'} up to age{' '}
                <span className="text-[#7B61FF] font-medium">{userAge}</span>
              </>
            )}
          </p>
        </div>
      </motion.div>

      {/* Timeline */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-24">
        <AnimatePresence mode="popLayout">
          {filteredAchievements.length === 0 ? (
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={{ duration: 0.3 }}
              className="flex flex-col items-center justify-center py-12"
            >
              <div className="w-24 h-24 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center mb-6 shadow-2xl shadow-[#7B61FF]/20">
                <span className="text-white text-3xl font-medium">{userAge}</span>
              </div>
              <h2 className="text-white text-xl mb-3">No achievements at this age</h2>
              <p className="text-[#A1A1AA] text-center max-w-xs">
                Try adjusting the age slider or switch to "Up to age" mode
              </p>
            </motion.div>
          ) : (
            <div className="space-y-3">
              {filteredAchievements.map((item, idx) => (
                <motion.div
                  key={`${item.age}-${item.achievement}`}
                  layout
                  initial={{ opacity: 0, scale: 0.95, y: 20 }}
                  animate={{ opacity: 1, scale: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.95, y: -20 }}
                  transition={{ 
                    layout: { type: 'spring', stiffness: 300, damping: 30 },
                    opacity: { duration: 0.3 },
                    scale: { duration: 0.3 },
                    y: { duration: 0.3 },
                    delay: idx * 0.05
                  }}
                >
                  <TimelineRow {...item} onOpenEvidence={() => handleOpenEvidence(item)} />
                </motion.div>
              ))}
            </div>
          )}
        </AnimatePresence>
      </div>

      {/* Evidence Sheet */}
      {evidenceSheetOpen && selectedAchievement && (
        <EvidenceSheet
          isOpen={evidenceSheetOpen}
          onClose={() => setEvidenceSheetOpen(false)}
          achievement={selectedAchievement}
          isLoading={isLoadingEvidence}
        />
      )}
    </div>
  );
}