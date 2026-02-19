import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Check, Plus, Settings2, User, ChevronRight, Sparkles } from 'lucide-react';

interface Idol {
  id: string;
  name: string;
  description: string;
  avatar?: string;
  closeness?: number;
}

interface IdolSwitcherSheetProps {
  isOpen: boolean;
  onClose: () => void;
  onSelectIdol: (idol: Idol) => void;
  onAddNewIdol: () => void;
  onManageIdols?: () => void;
  currentIdol?: Idol;
  savedIdols?: Idol[];
}

// Mock data
const mockCurrentIdol: Idol = {
  id: '1',
  name: 'Warren Buffett',
  description: 'Business Magnate, Investor',
  avatar: 'https://api.dicebear.com/7.x/initials/svg?seed=WB&backgroundColor=7B61FF',
  closeness: 68,
};

const mockSavedIdols: Idol[] = [
  {
    id: '2',
    name: 'Elon Musk',
    description: 'Entrepreneur, Engineer',
    avatar: 'https://api.dicebear.com/7.x/initials/svg?seed=EM&backgroundColor=60A5FA',
    closeness: 45,
  },
  {
    id: '3',
    name: 'Marie Curie',
    description: 'Physicist, Chemist',
    avatar: 'https://api.dicebear.com/7.x/initials/svg?seed=MC&backgroundColor=F472B6',
    closeness: 52,
  },
  {
    id: '4',
    name: 'Steve Jobs',
    description: 'Entrepreneur, Innovator',
    avatar: 'https://api.dicebear.com/7.x/initials/svg?seed=SJ&backgroundColor=FBBF24',
    closeness: 38,
  },
];

export function IdolSwitcherSheet({
  isOpen,
  onClose,
  onSelectIdol,
  onAddNewIdol,
  onManageIdols,
  currentIdol = mockCurrentIdol,
  savedIdols = mockSavedIdols,
}: IdolSwitcherSheetProps) {
  const handleSelectIdol = (idol: Idol) => {
    onSelectIdol(idol);
    onClose();
  };

  const handleAddNewIdol = () => {
    onAddNewIdol();
    onClose();
  };

  const handleManageIdols = () => {
    if (onManageIdols) {
      onManageIdols();
      onClose();
    }
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
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-white text-xl">Switch Idol</h2>
                  <p className="text-[#A1A1AA] text-sm mt-1">
                    Choose who to compare with
                  </p>
                </div>
                <motion.button
                  whileHover={{ scale: 1.1, rotate: 90 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={onClose}
                  className="w-8 h-8 rounded-full bg-[#121212] border border-[#2A2A2E] flex items-center justify-center"
                >
                  <X className="w-5 h-5 text-[#A1A1AA]" />
                </motion.button>
              </div>
            </div>

            {/* Content */}
            <div className="flex-1 overflow-y-auto px-6 py-6">
              {/* Current Idol Section */}
              <div className="mb-6">
                <p className="text-[#A1A1AA] text-xs mb-3 font-medium uppercase tracking-wide">
                  Current Idol
                </p>
                <motion.div
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: 0.1, duration: 0.3 }}
                  className="bg-[#121212] rounded-[20px] p-4 border-2 border-[#7B61FF] relative overflow-hidden"
                >
                  {/* Selected Badge */}
                  <div className="absolute top-0 right-0 px-3 py-1 bg-[#7B61FF] rounded-bl-[12px] rounded-tr-[18px]">
                    <div className="flex items-center gap-1">
                      <Check className="w-3 h-3 text-white" />
                      <span className="text-white text-xs font-medium">Active</span>
                    </div>
                  </div>

                  {/* Card Content */}
                  <div className="flex items-center gap-4">
                    {/* Avatar */}
                    <div className="w-16 h-16 rounded-full bg-[#7B61FF]/20 border-2 border-[#7B61FF] flex items-center justify-center flex-shrink-0">
                      <User className="w-8 h-8 text-[#7B61FF]" />
                    </div>

                    {/* Info */}
                    <div className="flex-1 min-w-0">
                      <h3 className="text-white font-medium mb-1">{currentIdol.name}</h3>
                      <p className="text-[#A1A1AA] text-sm mb-2">{currentIdol.description}</p>
                      
                      {/* Closeness Badge */}
                      {currentIdol.closeness !== undefined && (
                        <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/30">
                          <Sparkles className="w-3 h-3 text-[#7B61FF]" />
                          <span className="text-[#7B61FF] text-xs font-medium">
                            {currentIdol.closeness}% closeness
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                </motion.div>
              </div>

              {/* Saved Idols Section */}
              {savedIdols.length > 0 && (
                <div className="mb-6">
                  <p className="text-[#A1A1AA] text-xs mb-3 font-medium uppercase tracking-wide">
                    Your Idols ({savedIdols.length})
                  </p>
                  <div className="space-y-3">
                    {savedIdols.map((idol, index) => (
                      <motion.button
                        key={idol.id}
                        initial={{ opacity: 0, x: -20 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: 0.2 + index * 0.05, duration: 0.3 }}
                        whileHover={{ scale: 1.02, x: 4 }}
                        whileTap={{ scale: 0.98 }}
                        onClick={() => handleSelectIdol(idol)}
                        className="w-full bg-[#121212] rounded-[16px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
                      >
                        <div className="flex items-center gap-3">
                          {/* Avatar */}
                          <div className="w-12 h-12 rounded-full bg-[#2A2A2E] flex items-center justify-center flex-shrink-0">
                            <User className="w-6 h-6 text-[#A1A1AA]" />
                          </div>

                          {/* Info */}
                          <div className="flex-1 min-w-0">
                            <h4 className="text-white font-medium mb-0.5">{idol.name}</h4>
                            <p className="text-[#A1A1AA] text-sm">{idol.description}</p>
                          </div>

                          {/* Closeness or Chevron */}
                          {idol.closeness !== undefined ? (
                            <div className="flex items-center gap-2 flex-shrink-0">
                              <span className="text-[#7B61FF] text-sm font-medium">
                                {idol.closeness}%
                              </span>
                              <ChevronRight className="w-5 h-5 text-[#A1A1AA]" />
                            </div>
                          ) : (
                            <ChevronRight className="w-5 h-5 text-[#A1A1AA] flex-shrink-0" />
                          )}
                        </div>
                      </motion.button>
                    ))}
                  </div>
                </div>
              )}

              {/* Empty State */}
              {savedIdols.length === 0 && (
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.2 }}
                  className="text-center py-8"
                >
                  <div className="w-16 h-16 rounded-full bg-[#2A2A2E] flex items-center justify-center mx-auto mb-3">
                    <User className="w-8 h-8 text-[#A1A1AA]" />
                  </div>
                  <p className="text-[#A1A1AA] text-sm">No other idols saved</p>
                  <p className="text-[#A1A1AA] text-xs mt-1">
                    Add more idols to compare with
                  </p>
                </motion.div>
              )}
            </div>

            {/* Bottom Actions */}
            <div className="px-6 py-4 pb-8 border-t border-[#2A2A2E] bg-[#1C1C1E] space-y-3">
              {/* Primary CTA - Add New Idol */}
              <motion.button
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.3 }}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                onClick={handleAddNewIdol}
                className="w-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] rounded-[20px] p-4 flex items-center justify-center gap-2 shadow-lg shadow-[#7B61FF]/30 hover:shadow-xl hover:shadow-[#7B61FF]/40 transition-all"
              >
                <Plus className="w-5 h-5 text-white" />
                <span className="text-white font-medium">Add new idol</span>
              </motion.button>

              {/* Secondary CTA - Manage Idols */}
              {onManageIdols && (
                <motion.button
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.35 }}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={handleManageIdols}
                  className="w-full px-6 py-3.5 rounded-[16px] bg-[#121212] text-[#A1A1AA] border border-[#2A2A2E] hover:border-[#7B61FF]/30 hover:text-white transition-all flex items-center justify-center gap-2"
                >
                  <Settings2 className="w-4 h-4" />
                  <span className="font-medium">Manage idols</span>
                </motion.button>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
