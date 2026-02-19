import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Users } from 'lucide-react';
import { IdolSwitcherSheet } from '../IdolSwitcherSheet';

interface IdolSwitcherDemoScreenProps {
  onBack: () => void;
}

export function IdolSwitcherDemoScreen({ onBack }: IdolSwitcherDemoScreenProps) {
  const [showSwitcher, setShowSwitcher] = useState(false);
  const [currentIdol, setCurrentIdol] = useState({
    id: '1',
    name: 'Warren Buffett',
    description: 'Business Magnate, Investor',
    closeness: 68,
  });

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
        <h1 className="text-white text-2xl mb-2">Idol Switcher</h1>
        <p className="text-[#A1A1AA] text-sm">
          Demo: Switch between saved idols
        </p>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
        {/* Current Idol Display */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-6 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-xs mb-3 font-medium uppercase tracking-wide">
            Currently Comparing With
          </p>
          <div className="flex items-center gap-4">
            <div className="w-16 h-16 rounded-full bg-[#7B61FF]/20 border-2 border-[#7B61FF] flex items-center justify-center flex-shrink-0">
              <Users className="w-8 h-8 text-[#7B61FF]" />
            </div>
            <div className="flex-1">
              <h3 className="text-white font-medium text-lg mb-1">{currentIdol.name}</h3>
              <p className="text-[#A1A1AA] text-sm">{currentIdol.description}</p>
              <div className="mt-2 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/30">
                <span className="text-[#7B61FF] text-xs font-medium">
                  {currentIdol.closeness}% closeness
                </span>
              </div>
            </div>
          </div>
        </motion.div>

        {/* Open Switcher Button */}
        <motion.button
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          whileHover={{ scale: 1.02, x: 4 }}
          whileTap={{ scale: 0.98 }}
          onClick={() => setShowSwitcher(true)}
          className="w-full bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] rounded-[20px] p-4 shadow-lg shadow-[#7B61FF]/30 hover:shadow-xl hover:shadow-[#7B61FF]/40 transition-all"
        >
          <span className="text-white font-medium">Open Idol Switcher</span>
        </motion.button>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <h4 className="text-white font-medium mb-2">Features:</h4>
          <ul className="text-[#A1A1AA] text-sm space-y-2 leading-relaxed">
            <li>• Current idol shown at top with "Active" badge</li>
            <li>• List of saved idols with closeness percentages</li>
            <li>• Tap any idol to switch and compare</li>
            <li>• "Add new idol" button to discover more</li>
            <li>• Optional "Manage idols" for organization</li>
            <li>• Premium dark theme with smooth animations</li>
          </ul>
        </motion.div>

        {/* Selection Indicator */}
        {currentIdol.id !== '1' && (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-[#7B61FF]/10 rounded-[20px] p-4 border border-[#7B61FF]/30"
          >
            <p className="text-[#7B61FF] text-sm font-medium">
              ✓ Switched to {currentIdol.name}
            </p>
          </motion.div>
        )}
      </div>

      {/* Idol Switcher Sheet */}
      <IdolSwitcherSheet
        isOpen={showSwitcher}
        onClose={() => setShowSwitcher(false)}
        onSelectIdol={(idol) => {
          console.log('Selected idol:', idol);
          setCurrentIdol(idol);
        }}
        onAddNewIdol={() => {
          console.log('Navigate to idol discovery');
          // Navigate to idol suggestions/discovery flow
        }}
        onManageIdols={() => {
          console.log('Navigate to manage idols');
          // Navigate to idol management screen
        }}
      />
    </div>
  );
}
