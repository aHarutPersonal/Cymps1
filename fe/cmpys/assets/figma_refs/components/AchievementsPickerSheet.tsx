import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Search, Check } from 'lucide-react';

interface Achievement {
  id: string;
  title: string;
  category: string;
  categoryColor: string;
  date: string;
}

interface AchievementsPickerSheetProps {
  isOpen: boolean;
  onClose: () => void;
  onSelect: (achievement: Achievement) => void;
  selectedIds?: string[];
  multiSelect?: boolean;
}

// Mock achievements data
const mockAchievements: Achievement[] = [
  {
    id: '1',
    title: 'Saved $10,000 emergency fund',
    category: 'Finance',
    categoryColor: '#FBBF24',
    date: 'Mar 2024',
  },
  {
    id: '2',
    title: 'Started investing in index funds',
    category: 'Finance',
    categoryColor: '#FBBF24',
    date: 'Jan 2024',
  },
  {
    id: '3',
    title: 'Paid off student loans',
    category: 'Finance',
    categoryColor: '#FBBF24',
    date: 'Sep 2023',
  },
  {
    id: '4',
    title: 'Completed Python certification',
    category: 'Learning',
    categoryColor: '#60A5FA',
    date: 'Feb 2024',
  },
  {
    id: '5',
    title: 'Built first mobile app',
    category: 'Career',
    categoryColor: '#7B61FF',
    date: 'Dec 2023',
  },
  {
    id: '6',
    title: 'Launched side business',
    category: 'Career',
    categoryColor: '#7B61FF',
    date: 'Nov 2023',
  },
  {
    id: '7',
    title: 'Mentored 3 junior developers',
    category: 'Impact',
    categoryColor: '#F59E0B',
    date: 'Jan 2024',
  },
  {
    id: '8',
    title: 'Read 24 books this year',
    category: 'Learning',
    categoryColor: '#60A5FA',
    date: 'Dec 2023',
  },
];

export function AchievementsPickerSheet({
  isOpen,
  onClose,
  onSelect,
  selectedIds = [],
  multiSelect = false,
}: AchievementsPickerSheetProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [internalSelected, setInternalSelected] = useState<Set<string>>(new Set(selectedIds));

  const filteredAchievements = mockAchievements.filter((achievement) => {
    const query = searchQuery.toLowerCase();
    return (
      achievement.title.toLowerCase().includes(query) ||
      achievement.category.toLowerCase().includes(query)
    );
  });

  const handleSelect = (achievement: Achievement) => {
    if (multiSelect) {
      const newSelected = new Set(internalSelected);
      if (newSelected.has(achievement.id)) {
        newSelected.delete(achievement.id);
      } else {
        newSelected.add(achievement.id);
      }
      setInternalSelected(newSelected);
    } else {
      onSelect(achievement);
      onClose();
    }
  };

  const isSelected = (id: string) => {
    return internalSelected.has(id);
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.3 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50"
          />

          {/* Bottom Sheet */}
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 30, stiffness: 300 }}
            className="fixed bottom-0 left-0 right-0 bg-[#1C1C1E] rounded-t-[24px] border-t border-[#2A2A2E] z-50 max-h-[85vh] flex flex-col"
          >
            {/* Handle Bar */}
            <div className="flex justify-center pt-3 pb-2">
              <div className="w-10 h-1 bg-[#2A2A2E] rounded-full" />
            </div>

            {/* Header */}
            <div className="px-6 py-4 border-b border-[#2A2A2E]">
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-white text-xl">Select Achievement</h2>
                <motion.button
                  whileHover={{ scale: 1.1, rotate: 90 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={onClose}
                  className="w-8 h-8 rounded-full bg-[#121212] border border-[#2A2A2E] flex items-center justify-center"
                >
                  <X className="w-5 h-5 text-[#A1A1AA]" />
                </motion.button>
              </div>

              {/* Search Bar */}
              <div className="relative">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-[#A1A1AA] pointer-events-none" />
                <input
                  type="text"
                  placeholder="Search achievements..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-12 pr-4 py-3 bg-[#121212] border border-[#2A2A2E] rounded-[16px] text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-colors"
                />
              </div>
            </div>

            {/* Achievements List */}
            <div className="flex-1 overflow-y-auto px-6 py-4">
              {filteredAchievements.length === 0 ? (
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="text-center py-12"
                >
                  <p className="text-[#A1A1AA]">No achievements found</p>
                  <p className="text-[#A1A1AA] text-sm mt-2">Try a different search term</p>
                </motion.div>
              ) : (
                <div className="space-y-3 pb-6">
                  {filteredAchievements.map((achievement, index) => {
                    const selected = isSelected(achievement.id);
                    return (
                      <motion.button
                        key={achievement.id}
                        initial={{ opacity: 0, x: -20 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: index * 0.05, duration: 0.3 }}
                        whileHover={{ scale: 1.02, x: 4 }}
                        whileTap={{ scale: 0.98 }}
                        onClick={() => handleSelect(achievement)}
                        className={`w-full bg-[#121212] rounded-[16px] p-4 border transition-all text-left ${
                          selected
                            ? 'border-[#7B61FF] bg-[#7B61FF]/5'
                            : 'border-[#2A2A2E] hover:border-[#7B61FF]/30'
                        }`}
                      >
                        <div className="flex items-start gap-3">
                          <div className="flex-1 min-w-0">
                            <h3 className="text-white mb-2">{achievement.title}</h3>
                            <div className="flex items-center gap-2">
                              <div
                                className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium"
                                style={{
                                  backgroundColor: `${achievement.categoryColor}20`,
                                  color: achievement.categoryColor,
                                  border: `1px solid ${achievement.categoryColor}40`,
                                }}
                              >
                                {achievement.category}
                              </div>
                              <span className="text-[#A1A1AA] text-sm">{achievement.date}</span>
                            </div>
                          </div>

                          {/* Select Button/Indicator */}
                          {multiSelect ? (
                            <div
                              className={`w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0 mt-1 transition-all ${
                                selected
                                  ? 'bg-[#7B61FF] border-2 border-[#7B61FF]'
                                  : 'border-2 border-[#2A2A2E]'
                              }`}
                            >
                              {selected && <Check className="w-4 h-4 text-white" />}
                            </div>
                          ) : (
                            <motion.div
                              whileHover={{ scale: 1.1 }}
                              whileTap={{ scale: 0.9 }}
                              className="px-4 py-2 rounded-[12px] bg-[#7B61FF] text-white text-sm font-medium flex-shrink-0"
                            >
                              Select
                            </motion.div>
                          )}
                        </div>
                      </motion.button>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Multi-select Confirm Button */}
            {multiSelect && internalSelected.size > 0 && (
              <div className="px-6 py-4 border-t border-[#2A2A2E] bg-[#1C1C1E]">
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={() => {
                    // Return selected achievements
                    const selected = mockAchievements.filter((a) =>
                      internalSelected.has(a.id)
                    );
                    selected.forEach((a) => onSelect(a));
                    onClose();
                  }}
                  className="w-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] rounded-[20px] p-4 text-white font-medium shadow-lg shadow-[#7B61FF]/30"
                >
                  Confirm Selection ({internalSelected.size})
                </motion.button>
              </div>
            )}
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
