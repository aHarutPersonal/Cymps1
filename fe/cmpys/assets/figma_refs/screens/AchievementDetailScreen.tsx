import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, EllipsisVertical, Edit, Trash2, ExternalLink, Calendar, FileText } from 'lucide-react';

interface AchievementDetailScreenProps {
  onBack: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  onNavigate?: (screen: string) => void;
}

// Mock achievement data
const mockAchievement = {
  id: '1',
  title: 'Saved $10,000 emergency fund',
  category: 'Finance',
  categoryColor: '#FBBF24',
  date: 'March 15, 2024',
  age: 28,
  description: 'Successfully built a full emergency fund covering 6 months of expenses. Started with automated savings of $500/month and reached the goal in 18 months. This provides financial security and peace of mind for unexpected situations.',
  evidence: {
    url: 'https://bankstatement.example.com/savings',
    title: 'Bank Statement',
    domain: 'bankstatement.example.com',
    preview: 'Verified savings account balance showing $10,000 milestone achieved on March 15, 2024.',
  },
};

export function AchievementDetailScreen({ 
  onBack, 
  onEdit, 
  onDelete,
  onNavigate 
}: AchievementDetailScreenProps) {
  const [menuOpen, setMenuOpen] = useState(false);

  const handleDelete = () => {
    setMenuOpen(false);
    if (onDelete) {
      onDelete();
    } else {
      console.log('Delete achievement:', mockAchievement.id);
      // Show confirmation dialog then delete
    }
  };

  const handleEdit = () => {
    setMenuOpen(false);
    if (onEdit) {
      onEdit();
    } else {
      console.log('Edit achievement:', mockAchievement.id);
      onNavigate?.('add-achievement');
    }
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-6 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <div className="flex items-center justify-between mb-6">
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            onClick={onBack}
            className="p-2 -ml-2"
          >
            <ChevronLeft className="w-6 h-6 text-white" />
          </motion.button>

          {/* Overflow Menu */}
          <div className="relative">
            <motion.button
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              onClick={() => setMenuOpen(!menuOpen)}
              className="p-2 -mr-2 rounded-full hover:bg-[#1C1C1E] transition-colors"
            >
              <EllipsisVertical className="w-6 h-6 text-white" />
            </motion.button>

            {/* Dropdown Menu */}
            <AnimatePresence>
              {menuOpen && (
                <>
                  {/* Backdrop */}
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    onClick={() => setMenuOpen(false)}
                    className="fixed inset-0 z-40"
                  />

                  {/* Menu */}
                  <motion.div
                    initial={{ opacity: 0, scale: 0.95, y: -10 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    exit={{ opacity: 0, scale: 0.95, y: -10 }}
                    transition={{ duration: 0.2 }}
                    className="absolute right-0 top-12 w-48 bg-[#1C1C1E] rounded-[16px] border border-[#2A2A2E] overflow-hidden shadow-xl z-50"
                  >
                    <motion.button
                      whileHover={{ backgroundColor: '#252528' }}
                      whileTap={{ scale: 0.98 }}
                      onClick={handleEdit}
                      className="w-full px-4 py-3 flex items-center gap-3 text-left border-b border-[#2A2A2E]"
                    >
                      <Edit className="w-4 h-4 text-[#7B61FF]" />
                      <span className="text-white text-sm">Edit</span>
                    </motion.button>

                    <motion.button
                      whileHover={{ backgroundColor: '#252528' }}
                      whileTap={{ scale: 0.98 }}
                      onClick={handleDelete}
                      className="w-full px-4 py-3 flex items-center gap-3 text-left"
                    >
                      <Trash2 className="w-4 h-4 text-[#EF4444]" />
                      <span className="text-[#EF4444] text-sm">Delete</span>
                    </motion.button>
                  </motion.div>
                </>
              )}
            </AnimatePresence>
          </div>
        </div>

        <h1 className="text-white text-2xl">Achievement Details</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
        {/* Title */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
        >
          <h2 className="text-white text-xl mb-3">{mockAchievement.title}</h2>
          
          {/* Category Chip */}
          <div
            className="inline-flex items-center px-3 py-1.5 rounded-full text-sm font-medium"
            style={{
              backgroundColor: `${mockAchievement.categoryColor}20`,
              color: mockAchievement.categoryColor,
              border: `1px solid ${mockAchievement.categoryColor}40`,
            }}
          >
            {mockAchievement.category}
          </div>
        </motion.div>

        {/* Date */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center flex-shrink-0">
              <Calendar className="w-5 h-5 text-[#7B61FF]" />
            </div>
            <div>
              <p className="text-[#A1A1AA] text-xs mb-0.5">Date achieved</p>
              <p className="text-white">
                {mockAchievement.date}
                {mockAchievement.age && (
                  <span className="text-[#A1A1AA] ml-2">• Age {mockAchievement.age}</span>
                )}
              </p>
            </div>
          </div>
        </motion.div>

        {/* Description/Notes */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-full bg-[#60A5FA]/10 border border-[#60A5FA]/20 flex items-center justify-center flex-shrink-0 mt-0.5">
              <FileText className="w-5 h-5 text-[#60A5FA]" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[#A1A1AA] text-xs mb-2">Notes</p>
              <p className="text-white text-sm leading-relaxed">
                {mockAchievement.description}
              </p>
            </div>
          </div>
        </motion.div>

        {/* Evidence Link Preview (Optional) */}
        {mockAchievement.evidence && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4, duration: 0.5 }}
          >
            <h3 className="text-white mb-3">Evidence</h3>
            <motion.button
              whileHover={{ scale: 1.02, x: 4 }}
              whileTap={{ scale: 0.98 }}
              onClick={() => window.open(mockAchievement.evidence.url, '_blank')}
              className="w-full bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
            >
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 rounded-[12px] bg-[#34D399]/10 border border-[#34D399]/20 flex items-center justify-center flex-shrink-0">
                  <ExternalLink className="w-5 h-5 text-[#34D399]" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-1">
                    <h4 className="text-white font-medium">{mockAchievement.evidence.title}</h4>
                    <ExternalLink className="w-4 h-4 text-[#7B61FF] flex-shrink-0" />
                  </div>
                  <p className="text-[#A1A1AA] text-xs mb-2">{mockAchievement.evidence.domain}</p>
                  <p className="text-[#A1A1AA] text-sm line-clamp-2">
                    {mockAchievement.evidence.preview}
                  </p>
                </div>
              </div>
            </motion.button>
          </motion.div>
        )}

        {/* Bottom Padding */}
        <div className="h-6" />
      </div>
    </div>
  );
}