import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft } from 'lucide-react';
import { AchievementDetailScreen } from './AchievementDetailScreen';
import { AchievementsPickerSheet } from '../AchievementsPickerSheet';

interface AchievementDetailDemoScreenProps {
  onBack: () => void;
}

export function AchievementDetailDemoScreen({ onBack }: AchievementDetailDemoScreenProps) {
  const [showPicker, setShowPicker] = useState(false);
  const [selectedAchievement, setSelectedAchievement] = useState<any>(null);

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
        <h1 className="text-white text-2xl mb-2">Achievement Components</h1>
        <p className="text-[#A1A1AA] text-sm">
          Demo: Achievement Detail & Picker
        </p>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-4">
        {/* Option 1: View Achievement Detail */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => {
            // Navigate to achievement detail screen
            window.location.hash = '#achievement-detail';
          }}
          className="w-full bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
        >
          <h3 className="text-white mb-2 font-medium">Achievement Detail Screen</h3>
          <p className="text-[#A1A1AA] text-sm">
            View full achievement with title, category, date, notes, evidence, and edit/delete menu
          </p>
        </motion.button>

        {/* Option 2: Open Achievements Picker */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => setShowPicker(true)}
          className="w-full bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
        >
          <h3 className="text-white mb-2 font-medium">Achievements Picker Bottom Sheet</h3>
          <p className="text-[#A1A1AA] text-sm">
            Search and select achievements with category chips
          </p>
        </motion.button>

        {/* Selected Achievement Display */}
        {selectedAchievement && (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-[#7B61FF]/10 rounded-[20px] p-4 border border-[#7B61FF]/30"
          >
            <p className="text-[#A1A1AA] text-xs mb-2">Selected Achievement:</p>
            <p className="text-white font-medium">{selectedAchievement.title}</p>
            <p className="text-[#A1A1AA] text-sm mt-1">
              {selectedAchievement.category} • {selectedAchievement.date}
            </p>
          </motion.div>
        )}
      </div>

      {/* Achievements Picker Sheet */}
      <AchievementsPickerSheet
        isOpen={showPicker}
        onClose={() => setShowPicker(false)}
        onSelect={(achievement) => {
          console.log('Selected:', achievement);
          setSelectedAchievement(achievement);
        }}
      />
    </div>
  );
}
