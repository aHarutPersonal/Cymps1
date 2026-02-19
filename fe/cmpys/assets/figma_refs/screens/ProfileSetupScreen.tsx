import React, { useState } from 'react';
import { motion } from 'motion/react';
import { User, Calendar, Target, Sparkles } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface ProfileSetupScreenProps {
  onContinue: () => void;
}

const focusAreas = ['Career', 'Business', 'Finance', 'Health', 'Learning', 'Impact'];

export function ProfileSetupScreen({ onContinue }: ProfileSetupScreenProps) {
  const [name, setName] = useState('');
  const [age, setAge] = useState('');
  const [selectedFocus, setSelectedFocus] = useState<string[]>([]);

  const toggleFocus = (focus: string) => {
    setSelectedFocus((prev) =>
      prev.includes(focus) ? prev.filter((f) => f !== focus) : [...prev, focus]
    );
  };

  const canContinue = name.trim() && age.trim() && selectedFocus.length > 0;

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-6"
      >
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="w-16 h-16 rounded-[20px] bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-xl shadow-[#7B61FF]/30 mb-6"
        >
          <Sparkles className="w-8 h-8 text-white" />
        </motion.div>
        <h1 className="text-white text-3xl mb-3">Set up your profile</h1>
        <p className="text-[#A1A1AA] leading-relaxed">
          Tell us about yourself so we can create personalized comparisons
        </p>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32 space-y-6">
        {/* Name */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <User className="w-4 h-4" />
            What's your name?
          </label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Enter your name"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
            autoFocus
          />
        </motion.div>

        {/* Age */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <Calendar className="w-4 h-4" />
            How old are you?
          </label>
          <input
            type="number"
            value={age}
            onChange={(e) => setAge(e.target.value)}
            placeholder="Enter your age"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Focus Areas */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-3">
            <Target className="w-4 h-4" />
            What areas do you want to focus on?
          </label>
          <div className="flex flex-wrap gap-2">
            {focusAreas.map((focus, idx) => (
              <motion.button
                key={focus}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 0.5 + idx * 0.05, duration: 0.3 }}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => toggleFocus(focus)}
                className={`px-4 py-2 rounded-[14px] text-sm font-medium transition-all ${
                  selectedFocus.includes(focus)
                    ? 'bg-[#7B61FF]/20 border-2 border-[#7B61FF] text-white'
                    : 'bg-[#1C1C1E] border border-[#2A2A2E] text-[#A1A1AA]'
                }`}
              >
                {focus}
              </motion.button>
            ))}
          </div>
          <p className="text-[#A1A1AA] text-xs mt-3">
            Select one or more areas (you can change this later)
          </p>
        </motion.div>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.8, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            <span className="text-white font-medium">Why we ask:</span> Your age helps us show you what your idols achieved at your current age, making comparisons more meaningful.
          </p>
        </motion.div>
      </div>

      {/* Continue Button */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.9, duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-8 bg-gradient-to-t from-[#121212] via-[#121212] to-transparent border-t border-[#2A2A2E]"
      >
        <PrimaryButton onClick={onContinue} disabled={!canContinue}>
          Continue
        </PrimaryButton>
      </motion.div>
    </div>
  );
}
