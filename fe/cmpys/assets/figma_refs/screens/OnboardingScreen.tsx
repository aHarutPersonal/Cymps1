import React, { useState } from 'react';
import { motion } from 'motion/react';
import { PrimaryButton } from '../PrimaryButton';
import { TagChip } from '../TagChip';
import { ChevronLeft, Plus } from 'lucide-react';

interface OnboardingScreenProps {
  onContinue: () => void;
  onBack: () => void;
}

const initialFocusAreas = [
  'Career Growth',
  'Learning',
  'Finance',
  'Impact',
  'Health',
  'Creativity',
  'Leadership',
  'Entrepreneurship',
];

export function OnboardingScreen({ onContinue, onBack }: OnboardingScreenProps) {
  const [selected, setSelected] = useState<string[]>(['Career Growth', 'Learning']);
  const [focusAreas, setFocusAreas] = useState<string[]>(initialFocusAreas);
  const [customSkill, setCustomSkill] = useState('');
  const [showInput, setShowInput] = useState(false);

  const toggleSelection = (area: string) => {
    setSelected((prev) =>
      prev.includes(area) ? prev.filter((a) => a !== area) : [...prev, area]
    );
  };

  const addCustomSkill = () => {
    if (customSkill.trim() && !focusAreas.includes(customSkill.trim())) {
      setFocusAreas([...focusAreas, customSkill.trim()]);
      setSelected([...selected, customSkill.trim()]);
      setCustomSkill('');
      setShowInput(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      addCustomSkill();
    }
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      <motion.div
        initial={{ opacity: 0, x: -20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.3 }}
        className="p-6 pb-0"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
      </motion.div>
      <div className="flex-1 px-6 pt-8 pb-6 flex flex-col">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="mb-8"
        >
          <h1 className="text-white text-3xl mb-2">What's your focus?</h1>
          <p className="text-[#A1A1AA]">Select areas you want to improve</p>
        </motion.div>
        <div className="flex-1 overflow-y-auto">
          <div className="flex flex-wrap gap-3">
            {focusAreas.map((area, index) => (
              <motion.div
                key={area}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: index * 0.05, duration: 0.3 }}
              >
                <TagChip
                  label={area}
                  selected={selected.includes(area)}
                  onClick={() => toggleSelection(area)}
                />
              </motion.div>
            ))}
            {showInput && (
              <motion.div
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ duration: 0.3 }}
                className="flex items-center gap-2"
              >
                <input
                  type="text"
                  value={customSkill}
                  onChange={(e) => setCustomSkill(e.target.value)}
                  onKeyPress={handleKeyPress}
                  onBlur={() => {
                    if (!customSkill.trim()) {
                      setShowInput(false);
                    }
                  }}
                  autoFocus
                  className="bg-[#1C1C1E] text-white px-4 py-2 rounded-full border border-[#2A2A2E] focus:outline-none focus:border-[#7B61FF] placeholder-[#A1A1AA]"
                  placeholder="Type skill name..."
                />
                {customSkill.trim() && (
                  <motion.button
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1 }}
                    whileHover={{ scale: 1.1 }}
                    whileTap={{ scale: 0.9 }}
                    onClick={addCustomSkill}
                    className="w-8 h-8 rounded-full bg-[#7B61FF] flex items-center justify-center"
                  >
                    <Plus className="w-4 h-4 text-white" />
                  </motion.button>
                )}
              </motion.div>
            )}
            {!showInput && (
              <motion.div
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: focusAreas.length * 0.05, duration: 0.3 }}
              >
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => setShowInput(true)}
                  className="px-4 py-2 rounded-full bg-[#1C1C1E] text-[#A1A1AA] border border-[#2A2A2E] border-dashed flex items-center gap-2 transition-all hover:border-[#7B61FF] hover:text-[#7B61FF]"
                >
                  <Plus className="w-4 h-4" />
                  Add custom skill
                </motion.button>
              </motion.div>
            )}
          </div>
        </div>
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="pt-6"
        >
          <PrimaryButton onClick={onContinue}>Continue</PrimaryButton>
        </motion.div>
      </div>
    </div>
  );
}