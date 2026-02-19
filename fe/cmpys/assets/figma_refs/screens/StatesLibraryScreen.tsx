import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Play } from 'lucide-react';
import { TimelineLoadingSkeleton } from '../states/TimelineLoadingSkeleton';
import { PlanLoadingSkeleton } from '../states/PlanLoadingSkeleton';
import { EmptyPlanState } from '../states/EmptyPlanState';
import { EmptyAchievementsState } from '../states/EmptyAchievementsState';
import { ImportFailedState } from '../states/ImportFailedState';
import { OfflineBanner } from '../states/OfflineBanner';

interface StatesLibraryScreenProps {
  onBack: () => void;
}

type StateType = 
  | 'timelineSkeleton'
  | 'planSkeleton'
  | 'emptyPlan'
  | 'emptyAchievements'
  | 'importFailed'
  | 'offlineBanner';

const states = [
  { id: 'timelineSkeleton' as const, label: 'Timeline Loading', description: 'Skeleton for timeline items' },
  { id: 'planSkeleton' as const, label: 'Plan Loading', description: 'Skeleton for plan items' },
  { id: 'emptyPlan' as const, label: 'Empty Plan', description: 'No plans created yet' },
  { id: 'emptyAchievements' as const, label: 'Empty Achievements', description: 'No achievements added' },
  { id: 'importFailed' as const, label: 'Import Failed', description: 'Error importing idol' },
  { id: 'offlineBanner' as const, label: 'Offline Banner', description: 'No internet connection' },
];

export function StatesLibraryScreen({ onBack }: StatesLibraryScreenProps) {
  const [selectedState, setSelectedState] = useState<StateType>('timelineSkeleton');
  const [showOfflineBanner, setShowOfflineBanner] = useState(true);

  const renderState = () => {
    switch (selectedState) {
      case 'timelineSkeleton':
        return (
          <div className="px-6">
            <TimelineLoadingSkeleton />
          </div>
        );
      case 'planSkeleton':
        return (
          <div className="px-6">
            <PlanLoadingSkeleton />
          </div>
        );
      case 'emptyPlan':
        return (
          <div className="px-6">
            <EmptyPlanState 
              onGeneratePlan={() => console.log('Generate plan clicked')}
            />
          </div>
        );
      case 'emptyAchievements':
        return (
          <div className="px-6">
            <EmptyAchievementsState 
              onAddAchievement={() => console.log('Add achievement clicked')}
            />
          </div>
        );
      case 'importFailed':
        return (
          <div className="px-6">
            <ImportFailedState
              onRetry={() => console.log('Retry clicked')}
              onGoBack={() => console.log('Go back clicked')}
            />
          </div>
        );
      case 'offlineBanner':
        return (
          <div className="px-6 pt-8">
            <OfflineBanner 
              isVisible={showOfflineBanner}
              onDismiss={() => setShowOfflineBanner(false)}
            />
            <div className="mt-24 bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] text-center">
              <p className="text-[#A1A1AA] mb-4">
                The offline banner appears at the top of the screen
              </p>
              <motion.button
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => setShowOfflineBanner(true)}
                className="px-6 py-3 rounded-[16px] bg-[#7B61FF] text-white flex items-center gap-2 mx-auto"
              >
                <Play className="w-5 h-5" />
                <span>Show banner again</span>
              </motion.button>
            </div>
          </div>
        );
      default:
        return null;
    }
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-4 border-b border-[#2A2A2E] bg-[#121212] relative z-10"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-white text-2xl mb-1">States library</h1>
            <p className="text-[#A1A1AA] text-sm">Reusable UI state components</p>
          </div>
          <div className="px-3 py-1.5 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20">
            <span className="text-[#7B61FF] text-xs font-medium">{states.length} states</span>
          </div>
        </div>
      </motion.div>

      {/* State Selector */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.1, duration: 0.5 }}
        className="px-6 py-4 border-b border-[#2A2A2E] bg-[#121212] relative z-10"
      >
        <div className="flex gap-2 overflow-x-auto scrollbar-hide pb-1">
          {states.map((state) => (
            <motion.button
              key={state.id}
              onClick={() => {
                setSelectedState(state.id);
                if (state.id === 'offlineBanner') {
                  setShowOfflineBanner(true);
                }
              }}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              className={`px-4 py-2.5 rounded-[12px] border transition-all whitespace-nowrap flex-shrink-0 ${
                selectedState === state.id
                  ? 'bg-[#7B61FF] border-[#7B61FF] text-white'
                  : 'bg-[#1C1C1E] border-[#2A2A2E] text-[#A1A1AA] hover:border-[#7B61FF]/30'
              }`}
            >
              <div className="text-sm font-medium">{state.label}</div>
            </motion.button>
          ))}
        </div>
      </motion.div>

      {/* State Description */}
      <motion.div
        key={selectedState}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.3 }}
        className="px-6 py-3 border-b border-[#2A2A2E] bg-[#121212] relative z-10"
      >
        <p className="text-[#A1A1AA] text-sm">
          {states.find(s => s.id === selectedState)?.description}
        </p>
      </motion.div>

      {/* Content Area */}
      <div className="flex-1 overflow-y-auto py-6 relative">
        <motion.div
          key={selectedState}
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.4 }}
        >
          {renderState()}
        </motion.div>
      </div>

      {/* Component Info Footer */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.3, duration: 0.5 }}
        className="px-6 py-4 border-t border-[#2A2A2E] bg-[#121212] relative z-10"
      >
        <div className="bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E]">
          <h3 className="text-white text-sm mb-2">Component details</h3>
          <div className="space-y-2">
            {selectedState === 'timelineSkeleton' && (
              <>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">3 skeleton items with pulsing animation</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Staggered entrance for smooth loading</span>
                </div>
              </>
            )}
            {selectedState === 'planSkeleton' && (
              <>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">4 plan items with checkbox skeleton</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Optimized for checklist layout</span>
                </div>
              </>
            )}
            {selectedState === 'emptyPlan' && (
              <>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Animated gradient icon with sparkle badge</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Primary CTA with feature list</span>
                </div>
              </>
            )}
            {selectedState === 'emptyAchievements' && (
              <>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Trophy icon with floating animation</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Helpful context for first-time users</span>
                </div>
              </>
            )}
            {selectedState === 'importFailed' && (
              <>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Red gradient error icon with pulse</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Retry action + troubleshooting tips</span>
                </div>
              </>
            )}
            {selectedState === 'offlineBanner' && (
              <>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Slide-down animation from top</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]" />
                  <span className="text-[#A1A1AA] text-xs">Dismissible with smooth exit</span>
                </div>
              </>
            )}
          </div>
        </div>
      </motion.div>
    </div>
  );
}
