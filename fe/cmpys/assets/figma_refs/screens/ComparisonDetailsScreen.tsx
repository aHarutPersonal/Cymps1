import React from 'react';
import { motion } from 'motion/react';
import { ProgressCard } from '../ProgressCard';
import { ChevronLeft, TrendingUp, TrendingDown, Sparkles, Plus, CircleHelp } from 'lucide-react';

interface ComparisonDetailsScreenProps {
  onBack: () => void;
  onNavigate?: (screen: string) => void;
}

const progressItems = [
  { label: 'Career', progress: 68, color: '#7B61FF' },
  { label: 'Learning', progress: 75, color: '#60A5FA' },
  { label: 'Finance', progress: 45, color: '#34D399' },
  { label: 'Impact', progress: 52, color: '#F59E0B' },
];

const strengths = [
  { area: 'Learning Velocity', description: 'Completing courses faster than average' },
  { area: 'Technical Skills', description: 'Strong programming foundation' },
  { area: 'Networking', description: 'Active community engagement' },
];

const gaps = [
  { area: 'Business Experience', description: 'Limited startup experience' },
  { area: 'Public Speaking', description: 'Less conference presentations' },
  { area: 'Investment Portfolio', description: 'Smaller investment diversity' },
];

export function ComparisonDetailsScreen({ onBack, onNavigate }: ComparisonDetailsScreenProps) {
  const handleWhatCounts = (category: string) => {
    console.log(`What counts for ${category}?`);
    // Could open a modal or bottom sheet explaining criteria
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-6 border-b border-[#2A2A2E]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-3xl mb-1">Comparison</h1>
        <p className="text-[#A1A1AA]">You vs. Elon Musk at 28</p>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
        {/* Progress Breakdown */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E] space-y-4"
        >
          <h2 className="text-white mb-2">Progress Breakdown</h2>
          {progressItems.map((item, index) => (
            <div key={item.label}>
              <ProgressCard {...item} />
              {index < progressItems.length - 1 && (
                <motion.button
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.3 + index * 0.1 }}
                  whileHover={{ x: 2 }}
                  onClick={() => handleWhatCounts(item.label)}
                  className="flex items-center gap-1 mt-2 mb-2 text-[#A1A1AA] text-xs hover:text-[#7B61FF] transition-colors"
                >
                  <CircleHelp className="w-3 h-3" />
                  <span>What counts?</span>
                </motion.button>
              )}
              {index === progressItems.length - 1 && (
                <motion.button
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.3 + index * 0.1 }}
                  whileHover={{ x: 2 }}
                  onClick={() => handleWhatCounts(item.label)}
                  className="flex items-center gap-1 mt-2 text-[#A1A1AA] text-xs hover:text-[#7B61FF] transition-colors"
                >
                  <CircleHelp className="w-3 h-3" />
                  <span>What counts?</span>
                </motion.button>
              )}
            </div>
          ))}
        </motion.div>

        {/* Strengths */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.5 }}
        >
          <div className="flex items-center gap-2 mb-4">
            <TrendingUp className="w-5 h-5 text-[#34D399]" />
            <h2 className="text-white">Your Strengths</h2>
          </div>
          <div className="space-y-3">
            {strengths.map((item, idx) => (
              <motion.div
                key={idx}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.5 + idx * 0.1, duration: 0.5 }}
                className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] border-l-4 border-l-[#34D399]"
              >
                <h3 className="text-white mb-1">{item.area}</h3>
                <p className="text-[#A1A1AA] text-sm">{item.description}</p>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* Gaps */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.8, duration: 0.5 }}
        >
          <div className="flex items-center gap-2 mb-4">
            <TrendingDown className="w-5 h-5 text-[#F59E0B]" />
            <h2 className="text-white">Areas to Improve</h2>
          </div>
          <div className="space-y-3">
            {gaps.map((item, idx) => (
              <motion.div
                key={idx}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.9 + idx * 0.1, duration: 0.5 }}
                className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] border-l-4 border-l-[#F59E0B]"
              >
                <h3 className="text-white mb-1">{item.area}</h3>
                <p className="text-[#A1A1AA] text-sm">{item.description}</p>
              </motion.div>
            ))}
          </div>
        </motion.div>

        {/* CTAs */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.2, duration: 0.5 }}
          className="space-y-3 pt-2"
        >
          {/* Primary CTA - Generate Plan */}
          <motion.button
            whileHover={{ scale: 1.02, y: -2 }}
            whileTap={{ scale: 0.98 }}
            onClick={() => onNavigate?.('plan-tracker')}
            className="w-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] rounded-[20px] p-4 flex items-center justify-center gap-2 shadow-lg shadow-[#7B61FF]/30 hover:shadow-xl hover:shadow-[#7B61FF]/40 transition-all"
          >
            <Sparkles className="w-5 h-5 text-white" />
            <span className="text-white font-medium">Generate plan from gaps</span>
          </motion.button>

          {/* Secondary CTA - Add Achievement */}
          <motion.button
            whileHover={{ scale: 1.02, y: -2 }}
            whileTap={{ scale: 0.98 }}
            onClick={() => onNavigate?.('add-achievement')}
            className="w-full bg-[#1C1C1E] border-2 border-[#7B61FF]/30 rounded-[20px] p-4 flex items-center justify-center gap-2 hover:border-[#7B61FF]/50 hover:bg-[#7B61FF]/5 transition-all"
          >
            <Plus className="w-5 h-5 text-[#7B61FF]" />
            <span className="text-[#7B61FF] font-medium">Add achievement</span>
          </motion.button>
        </motion.div>

        {/* Bottom Padding */}
        <div className="h-6" />
      </div>
    </div>
  );
}