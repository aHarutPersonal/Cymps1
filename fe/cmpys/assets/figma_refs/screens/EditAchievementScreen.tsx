import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Calendar as CalendarIcon, Hash, AlignLeft, Link as LinkIcon } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface EditAchievementScreenProps {
  onBack: () => void;
  onSave: (achievement: any) => void;
  initialData?: {
    title?: string;
    category?: string;
    date?: string;
    description?: string;
    evidence?: string;
  };
}

const categories = [
  { id: 'technical', label: 'Technical', color: '#60A5FA' },
  { id: 'leadership', label: 'Leadership', color: '#A78BFA' },
  { id: 'impact', label: 'Impact', color: '#F59E0B' },
  { id: 'growth', label: 'Growth', color: '#4ADE80' },
  { id: 'innovation', label: 'Innovation', color: '#EC4899' },
];

const mockInitialData = {
  title: 'Mentored 3 junior developers',
  category: 'impact',
  date: '2024-01',
  description: 'Provided guidance and mentorship to three junior developers, helping them improve their coding skills and career development.',
  evidence: 'https://linkedin.com/posts/mentorship-program',
};

export function EditAchievementScreen({ 
  onBack, 
  onSave,
  initialData = mockInitialData 
}: EditAchievementScreenProps) {
  const [title, setTitle] = useState(initialData.title || '');
  const [category, setCategory] = useState(initialData.category || '');
  const [date, setDate] = useState(initialData.date || '');
  const [description, setDescription] = useState(initialData.description || '');
  const [evidence, setEvidence] = useState(initialData.evidence || '');

  const handleSave = () => {
    onSave({
      title,
      category,
      date,
      description,
      evidence,
    });
  };

  const canSave = title.trim() && category && date;

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
        <h1 className="text-white text-2xl">Edit Achievement</h1>
      </motion.div>

      {/* Form */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32 space-y-5">
        {/* Title */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <Hash className="w-4 h-4" />
            Title
          </label>
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. Led team to launch new product"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Category */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-3">
            Category
          </label>
          <div className="flex flex-wrap gap-2">
            {categories.map((cat, idx) => (
              <motion.button
                key={cat.id}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: 0.3 + idx * 0.05, duration: 0.3 }}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => setCategory(cat.id)}
                className={`px-4 py-2 rounded-[14px] text-sm font-medium transition-all ${
                  category === cat.id
                    ? 'text-white border-2'
                    : 'text-[#A1A1AA] bg-[#1C1C1E] border border-[#2A2A2E]'
                }`}
                style={
                  category === cat.id
                    ? {
                        backgroundColor: `${cat.color}20`,
                        borderColor: cat.color,
                      }
                    : {}
                }
              >
                {cat.label}
              </motion.button>
            ))}
          </div>
        </motion.div>

        {/* Date */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <CalendarIcon className="w-4 h-4" />
            Date (YYYY-MM)
          </label>
          <input
            type="text"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            placeholder="e.g. 2024-01"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Description */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <AlignLeft className="w-4 h-4" />
            Description (optional)
          </label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Describe what you accomplished..."
            rows={4}
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all resize-none"
          />
        </motion.div>

        {/* Evidence Link */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <LinkIcon className="w-4 h-4" />
            Evidence Link (optional)
          </label>
          <input
            type="url"
            value={evidence}
            onChange={(e) => setEvidence(e.target.value)}
            placeholder="https://..."
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.7, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            Edit your achievement details. Changes will be reflected in your timeline and comparisons.
          </p>
        </motion.div>
      </div>

      {/* Save Button */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.8, duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-8 bg-gradient-to-t from-[#121212] via-[#121212] to-transparent border-t border-[#2A2A2E]"
      >
        <PrimaryButton onClick={handleSave} disabled={!canSave}>
          Save changes
        </PrimaryButton>
      </motion.div>
    </div>
  );
}
