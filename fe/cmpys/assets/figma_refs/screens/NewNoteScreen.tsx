import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, Paperclip, Target, Trophy, User } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface NewNoteScreenProps {
  onBack: () => void;
  onSave: (note: { title: string; body: string; attachments: string[] }) => void;
}

type AttachmentType = 'plan' | 'achievement' | 'idol';

const attachmentOptions: { type: AttachmentType; label: string; icon: React.ReactNode; color: string }[] = [
  { type: 'plan', label: 'Attach plan item', icon: <Target className="w-4 h-4" />, color: '#7B61FF' },
  { type: 'achievement', label: 'Attach achievement', icon: <Trophy className="w-4 h-4" />, color: '#4ADE80' },
  { type: 'idol', label: 'Attach idol', icon: <User className="w-4 h-4" />, color: '#FBBF24' },
];

export function NewNoteScreen({ onBack, onSave }: NewNoteScreenProps) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [selectedAttachments, setSelectedAttachments] = useState<AttachmentType[]>([]);

  const toggleAttachment = (type: AttachmentType) => {
    setSelectedAttachments((prev) =>
      prev.includes(type) ? prev.filter((t) => t !== type) : [...prev, type]
    );
  };

  const handleSave = () => {
    if (!body.trim()) {
      return; // Don't save empty notes
    }
    onSave({
      title: title.trim(),
      body: body.trim(),
      attachments: selectedAttachments,
    });
  };

  const canSave = body.trim().length > 0;

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-4 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <div className="flex items-center justify-between mb-2">
          <motion.button
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            onClick={onBack}
            className="p-2 -ml-2"
          >
            <ChevronLeft className="w-6 h-6 text-white" />
          </motion.button>
          <span className="text-[#A1A1AA] text-sm">
            {body.length} characters
          </span>
        </div>
        <h1 className="text-white text-2xl">New note</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32">
        {/* Title Input */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.4 }}
          className="mb-4"
        >
          <input
            type="text"
            placeholder="Title (optional)"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="w-full bg-transparent border-b border-[#2A2A2E] pb-3 text-white text-xl placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Body Editor */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.4 }}
          className="mb-6"
        >
          <textarea
            placeholder="Start writing your note..."
            value={body}
            onChange={(e) => setBody(e.target.value)}
            className="w-full bg-transparent text-white placeholder-[#A1A1AA] focus:outline-none resize-none leading-relaxed"
            rows={12}
            autoFocus
          />
        </motion.div>

        {/* Attach Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          {/* Section Header */}
          <div className="flex items-center gap-2 mb-4">
            <Paperclip className="w-5 h-5 text-[#7B61FF]" />
            <h3 className="text-white font-medium">Attach</h3>
          </div>

          {/* Attachment Pills */}
          <div className="space-y-2">
            {attachmentOptions.map((option, index) => (
              <motion.button
                key={option.type}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.4 + index * 0.1, duration: 0.4 }}
                onClick={() => toggleAttachment(option.type)}
                whileHover={{ scale: 1.02, x: 4 }}
                whileTap={{ scale: 0.98 }}
                className={`w-full flex items-center gap-3 px-4 py-3 rounded-[16px] border-2 transition-all ${
                  selectedAttachments.includes(option.type)
                    ? 'bg-[#7B61FF]/10 border-[#7B61FF]'
                    : 'bg-[#121212] border-[#2A2A2E] hover:border-[#7B61FF]/30'
                }`}
              >
                {/* Icon */}
                <div
                  className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0"
                  style={{
                    backgroundColor: `${option.color}20`,
                    border: `1px solid ${option.color}40`,
                  }}
                >
                  <div style={{ color: option.color }}>{option.icon}</div>
                </div>

                {/* Label */}
                <span
                  className={`flex-1 text-left ${
                    selectedAttachments.includes(option.type)
                      ? 'text-white'
                      : 'text-[#A1A1AA]'
                  }`}
                >
                  {option.label}
                </span>

                {/* Checkmark */}
                {selectedAttachments.includes(option.type) && (
                  <motion.div
                    initial={{ scale: 0 }}
                    animate={{ scale: 1 }}
                    transition={{ type: 'spring', stiffness: 300, damping: 20 }}
                    className="w-6 h-6 rounded-full bg-[#7B61FF] flex items-center justify-center flex-shrink-0"
                  >
                    <svg
                      className="w-4 h-4 text-white"
                      fill="none"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path d="M5 13l4 4L19 7" />
                    </svg>
                  </motion.div>
                )}
              </motion.button>
            ))}
          </div>

          {/* Selected Count */}
          {selectedAttachments.length > 0 && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              className="mt-3 pt-3 border-t border-[#2A2A2E]"
            >
              <p className="text-[#A1A1AA] text-xs">
                {selectedAttachments.length}{' '}
                {selectedAttachments.length === 1 ? 'attachment' : 'attachments'} selected
              </p>
            </motion.div>
          )}
        </motion.div>

        {/* Info Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.7, duration: 0.4 }}
          className="mt-4 bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            Attach context to your notes to keep them connected to your journey. You can link plan
            items, achievements, or idol milestones.
          </p>
        </motion.div>
      </div>

      {/* Sticky Save Button */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.8, duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-8 bg-gradient-to-t from-[#121212] via-[#121212] to-transparent border-t border-[#2A2A2E]"
      >
        <PrimaryButton onClick={handleSave} disabled={!canSave}>
          Save note
        </PrimaryButton>
      </motion.div>
    </div>
  );
}