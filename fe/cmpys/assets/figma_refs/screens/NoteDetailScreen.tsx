import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, EllipsisVertical, Edit, Trash2, Calendar, FileText, Target, Trophy, User, ChevronRight } from 'lucide-react';

interface NoteDetailScreenProps {
  onBack: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  onNavigate?: (screen: string) => void;
}

// Mock note data
const mockNote = {
  id: '1',
  title: 'Weekly reflection on progress',
  date: 'January 5, 2026',
  time: '2:30 PM',
  body: `Had a productive week working on my career goals. The mentorship sessions with the junior developers have been incredibly rewarding and helped me refine my own understanding of system architecture.

Realized that my approach to financial planning needs more structure. Warren Buffett's disciplined approach to investments at my age is inspiring - need to be more methodical about diversification.

Key insight: Consistency beats intensity. Small daily actions compound over time.`,
  attachments: {
    idol: {
      id: '1',
      name: 'Warren Buffett',
      description: 'Business Magnate, Investor',
      avatar: 'https://api.dicebear.com/7.x/initials/svg?seed=WB&backgroundColor=7B61FF',
    },
    planItem: {
      id: '1',
      title: 'Complete advanced investing course',
      category: 'Finance',
      categoryColor: '#FBBF24',
      dueDate: 'Feb 15, 2026',
    },
    achievement: {
      id: '1',
      title: 'Mentored 3 junior developers',
      category: 'Impact',
      categoryColor: '#F59E0B',
      date: 'Jan 2024',
    },
  },
};

export function NoteDetailScreen({ 
  onBack, 
  onEdit, 
  onDelete,
  onNavigate 
}: NoteDetailScreenProps) {
  const [menuOpen, setMenuOpen] = useState(false);

  const handleDelete = () => {
    setMenuOpen(false);
    if (onDelete) {
      onDelete();
    } else {
      console.log('Delete note:', mockNote.id);
      // Show confirmation dialog then delete
    }
  };

  const handleEdit = () => {
    setMenuOpen(false);
    if (onEdit) {
      onEdit();
    } else {
      console.log('Edit note:', mockNote.id);
      onNavigate?.('edit-note');
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

        <h1 className="text-white text-2xl">Note</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 space-y-6">
        {/* Title (Optional) */}
        {mockNote.title && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1, duration: 0.5 }}
          >
            <h2 className="text-white text-xl">{mockNote.title}</h2>
          </motion.div>
        )}

        {/* Date & Time */}
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
              <p className="text-[#A1A1AA] text-xs mb-0.5">Created</p>
              <p className="text-white">
                {mockNote.date}
                <span className="text-[#A1A1AA] ml-2">• {mockNote.time}</span>
              </p>
            </div>
          </div>
        </motion.div>

        {/* Full Text */}
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
              <p className="text-[#A1A1AA] text-xs mb-3">Note</p>
              <p className="text-white text-sm leading-relaxed whitespace-pre-wrap">
                {mockNote.body}
              </p>
            </div>
          </div>
        </motion.div>

        {/* Attachments Section */}
        {(mockNote.attachments.idol || mockNote.attachments.planItem || mockNote.attachments.achievement) && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4, duration: 0.5 }}
          >
            <h3 className="text-white mb-3 font-medium">Attachments</h3>
            <div className="space-y-3">
              {/* Attached Idol */}
              {mockNote.attachments.idol && (
                <motion.button
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.5, duration: 0.4 }}
                  whileHover={{ scale: 1.02, x: 4 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={() => onNavigate?.('idol-timeline')}
                  className="w-full bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E] hover:border-[#FBBF24]/30 transition-all text-left"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full bg-[#FBBF24]/10 border border-[#FBBF24]/20 flex items-center justify-center flex-shrink-0">
                      <User className="w-5 h-5 text-[#FBBF24]" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[#FBBF24] text-xs mb-1 font-medium">IDOL</p>
                      <h4 className="text-white font-medium mb-0.5">{mockNote.attachments.idol.name}</h4>
                      <p className="text-[#A1A1AA] text-sm">{mockNote.attachments.idol.description}</p>
                    </div>
                    <ChevronRight className="w-5 h-5 text-[#A1A1AA] flex-shrink-0" />
                  </div>
                </motion.button>
              )}

              {/* Attached Plan Item */}
              {mockNote.attachments.planItem && (
                <motion.button
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.6, duration: 0.4 }}
                  whileHover={{ scale: 1.02, x: 4 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={() => onNavigate?.('plan-tracker')}
                  className="w-full bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20 flex items-center justify-center flex-shrink-0">
                      <Target className="w-5 h-5 text-[#7B61FF]" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[#7B61FF] text-xs mb-1 font-medium">PLAN ITEM</p>
                      <h4 className="text-white font-medium mb-1">{mockNote.attachments.planItem.title}</h4>
                      <div className="flex items-center gap-2">
                        <div
                          className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"
                          style={{
                            backgroundColor: `${mockNote.attachments.planItem.categoryColor}20`,
                            color: mockNote.attachments.planItem.categoryColor,
                            border: `1px solid ${mockNote.attachments.planItem.categoryColor}40`,
                          }}
                        >
                          {mockNote.attachments.planItem.category}
                        </div>
                        <span className="text-[#A1A1AA] text-xs">Due {mockNote.attachments.planItem.dueDate}</span>
                      </div>
                    </div>
                    <ChevronRight className="w-5 h-5 text-[#A1A1AA] flex-shrink-0" />
                  </div>
                </motion.button>
              )}

              {/* Attached Achievement */}
              {mockNote.attachments.achievement && (
                <motion.button
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0.7, duration: 0.4 }}
                  whileHover={{ scale: 1.02, x: 4 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={() => onNavigate?.('achievement-detail')}
                  className="w-full bg-[#1C1C1E] rounded-[16px] p-4 border border-[#2A2A2E] hover:border-[#4ADE80]/30 transition-all text-left"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full bg-[#4ADE80]/10 border border-[#4ADE80]/20 flex items-center justify-center flex-shrink-0">
                      <Trophy className="w-5 h-5 text-[#4ADE80]" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[#4ADE80] text-xs mb-1 font-medium">ACHIEVEMENT</p>
                      <h4 className="text-white font-medium mb-1">{mockNote.attachments.achievement.title}</h4>
                      <div className="flex items-center gap-2">
                        <div
                          className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"
                          style={{
                            backgroundColor: `${mockNote.attachments.achievement.categoryColor}20`,
                            color: mockNote.attachments.achievement.categoryColor,
                            border: `1px solid ${mockNote.attachments.achievement.categoryColor}40`,
                          }}
                        >
                          {mockNote.attachments.achievement.category}
                        </div>
                        <span className="text-[#A1A1AA] text-xs">{mockNote.attachments.achievement.date}</span>
                      </div>
                    </div>
                    <ChevronRight className="w-5 h-5 text-[#A1A1AA] flex-shrink-0" />
                  </div>
                </motion.button>
              )}
            </div>
          </motion.div>
        )}

        {/* Bottom Padding */}
        <div className="h-6" />
      </div>
    </div>
  );
}
