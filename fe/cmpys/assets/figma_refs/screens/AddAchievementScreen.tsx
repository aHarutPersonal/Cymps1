import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, Calendar, Link2, AlertCircle, Briefcase, GraduationCap, DollarSign, Heart, Brain } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface AddAchievementScreenProps {
  onBack: () => void;
  onSave: (achievement: Achievement) => void;
}

interface Achievement {
  title: string;
  category: Category | null;
  date: string;
  notes: string;
  evidenceLink: string;
}

type Category = 'Career' | 'Learning' | 'Finance' | 'Impact' | 'Mindset';

const categories: { id: Category; label: string; icon: React.ReactNode }[] = [
  { id: 'Career', label: 'Career', icon: <Briefcase className="w-4 h-4" /> },
  { id: 'Learning', label: 'Learning', icon: <GraduationCap className="w-4 h-4" /> },
  { id: 'Finance', label: 'Finance', icon: <DollarSign className="w-4 h-4" /> },
  { id: 'Impact', label: 'Impact', icon: <Heart className="w-4 h-4" /> },
  { id: 'Mindset', label: 'Mindset', icon: <Brain className="w-4 h-4" /> },
];

export function AddAchievementScreen({ onBack, onSave }: AddAchievementScreenProps) {
  const [title, setTitle] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<Category | null>(null);
  const [date, setDate] = useState('');
  const [notes, setNotes] = useState('');
  const [evidenceLink, setEvidenceLink] = useState('');
  const [touched, setTouched] = useState(false);
  const [showDatePicker, setShowDatePicker] = useState(false);

  const isTitleValid = title.trim().length > 0;
  const showTitleError = touched && !isTitleValid;

  const handleSave = () => {
    setTouched(true);
    
    if (!isTitleValid) {
      return;
    }

    onSave({
      title,
      category: selectedCategory,
      date,
      notes,
      evidenceLink,
    });
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-4 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-2xl">Add achievement</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32">
        {/* Title Field */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="mb-6"
        >
          <label className="block text-white text-sm mb-3">
            Title <span className="text-[#7B61FF]">*</span>
          </label>
          <div className="relative">
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              onBlur={() => setTouched(true)}
              placeholder="e.g., Founded first company"
              className={`w-full px-4 py-4 rounded-[20px] bg-[#1C1C1E] text-white placeholder-[#A1A1AA] border-2 transition-all outline-none ${
                showTitleError
                  ? 'border-[#FF6B6B] focus:border-[#FF6B6B]'
                  : 'border-[#2A2A2E] focus:border-[#7B61FF]'
              }`}
            />
            <AnimatePresence>
              {showTitleError && (
                <motion.div
                  initial={{ opacity: 0, y: -10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  className="flex items-center gap-2 mt-2 text-[#FF6B6B] text-sm"
                >
                  <AlertCircle className="w-4 h-4" />
                  <span>Title is required</span>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </motion.div>

        {/* Category Chips */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="mb-6"
        >
          <label className="block text-white text-sm mb-3">Category</label>
          <div className="flex flex-wrap gap-2">
            {categories.map((category) => (
              <motion.button
                key={category.id}
                onClick={() => setSelectedCategory(category.id)}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className={`flex items-center gap-2 px-4 py-3 rounded-[16px] border-2 transition-all ${
                  selectedCategory === category.id
                    ? 'bg-[#7B61FF] border-[#7B61FF] text-white'
                    : 'bg-[#1C1C1E] border-[#2A2A2E] text-[#A1A1AA] hover:border-[#7B61FF]/30'
                }`}
              >
                {category.icon}
                <span className="text-sm">{category.label}</span>
              </motion.button>
            ))}
          </div>
        </motion.div>

        {/* Date Picker */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="mb-6"
        >
          <label className="block text-white text-sm mb-3">Date</label>
          <div className="relative">
            <div className="absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none">
              <Calendar className="w-5 h-5 text-[#A1A1AA]" />
            </div>
            <input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="w-full pl-12 pr-4 py-4 rounded-[20px] bg-[#1C1C1E] text-white border-2 border-[#2A2A2E] transition-all outline-none focus:border-[#7B61FF]"
              style={{
                colorScheme: 'dark',
              }}
            />
          </div>
        </motion.div>

        {/* Notes Field */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.5 }}
          className="mb-6"
        >
          <label className="block text-white text-sm mb-3">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Add context or details about this achievement..."
            rows={4}
            className="w-full px-4 py-4 rounded-[20px] bg-[#1C1C1E] text-white placeholder-[#A1A1AA] border-2 border-[#2A2A2E] transition-all outline-none focus:border-[#7B61FF] resize-none"
          />
          <div className="flex justify-end mt-2">
            <span className="text-[#A1A1AA] text-xs">{notes.length} characters</span>
          </div>
        </motion.div>

        {/* Evidence Link Field */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.5 }}
          className="mb-6"
        >
          <label className="block text-white text-sm mb-3">
            Evidence link <span className="text-[#A1A1AA] text-xs">(Optional)</span>
          </label>
          <div className="relative">
            <div className="absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none">
              <Link2 className="w-5 h-5 text-[#A1A1AA]" />
            </div>
            <input
              type="url"
              value={evidenceLink}
              onChange={(e) => setEvidenceLink(e.target.value)}
              placeholder="https://example.com/article"
              className="w-full pl-12 pr-4 py-4 rounded-[20px] bg-[#1C1C1E] text-white placeholder-[#A1A1AA] border-2 border-[#2A2A2E] transition-all outline-none focus:border-[#7B61FF]"
            />
          </div>
        </motion.div>

        {/* Helper Info */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <div className="flex gap-3">
            <AlertCircle className="w-5 h-5 text-[#7B61FF] flex-shrink-0 mt-0.5" />
            <p className="text-[#A1A1AA] text-sm leading-relaxed">
              Add your own achievements to compare with your idol's timeline and track your progress.
            </p>
          </div>
        </motion.div>
      </div>

      {/* Sticky Bottom Buttons */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.7, duration: 0.5 }}
        className="fixed bottom-0 left-0 right-0 px-6 py-4 pb-8 border-t border-[#2A2A2E] bg-[#121212]/95 backdrop-blur-lg"
        style={{ maxWidth: '390px', margin: '0 auto' }}
      >
        <div className="space-y-3">
          <PrimaryButton onClick={handleSave} disabled={!isTitleValid && touched}>
            Save achievement
          </PrimaryButton>
          
          <motion.button
            onClick={onBack}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className="w-full px-6 py-4 rounded-[20px] bg-transparent text-[#7B61FF] border-2 border-[#7B61FF]/30 transition-all hover:border-[#7B61FF]/50 hover:bg-[#7B61FF]/5"
          >
            Cancel
          </motion.button>
        </div>
      </motion.div>
    </div>
  );
}
