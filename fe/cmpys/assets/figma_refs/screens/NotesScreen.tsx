import React, { useState } from 'react';
import { motion } from 'motion/react';
import { Search, Plus, ChevronRight, FileText } from 'lucide-react';

interface NotesScreenProps {
  onBack: () => void;
  onCreateNote: () => void;
  onViewNote?: (noteId: string) => void;
}

const notes = [
  {
    id: '1',
    date: 'Jan 5, 2026',
    title: 'Reflection on Progress',
    content: "Today I completed 3 tasks from my plan. Feeling motivated about the learning journey. The comparison with Elon's timeline is eye-opening...",
    attachments: ['plan'],
  },
  {
    id: '2',
    date: 'Jan 4, 2026',
    title: 'Key Insights from Zero to One',
    content: 'Chapter 3 discusses monopolies vs competition. Important lesson: focus on creating unique value rather than competing in crowded markets.',
    attachments: [],
  },
  {
    id: '3',
    date: 'Jan 2, 2026',
    title: 'New Year Goals',
    content: 'Set ambitious goals for 2026. Want to close the gap in business experience and public speaking. Planning to attend more events.',
    attachments: ['achievement'],
  },
  {
    id: '4',
    date: 'Dec 28, 2025',
    title: 'Warren Buffett Quote',
    content: 'The most important investment you can make is in yourself. The more you learn, the more you earn.',
    attachments: ['idol'],
  },
  {
    id: '5',
    date: 'Dec 20, 2025',
    title: 'Meeting Notes - Q4 Review',
    content: 'Discussed progress on key initiatives. Team suggested focusing on customer retention. Need to improve onboarding flow.',
    attachments: [],
  },
];

export function NotesScreen({ onBack, onCreateNote, onViewNote }: NotesScreenProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [hasNotes] = useState(notes.length > 0); // Toggle this to test empty state

  const filteredNotes = notes.filter(
    (note) =>
      note.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      note.content.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleNoteClick = (noteId: string) => {
    if (onViewNote) {
      onViewNote(noteId);
    } else {
      console.log('View note:', noteId);
    }
  };

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-4 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <h1 className="text-white text-2xl mb-4">Notes</h1>

        {/* Search Field - Only show if there are notes */}
        {hasNotes && (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1, duration: 0.4 }}
            className="relative"
          >
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-[#A1A1AA]" />
            <input
              type="text"
              placeholder="Search notes..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] pl-12 pr-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
            />
          </motion.div>
        )}
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-40">
        {/* Empty State - No notes at all */}
        {!hasNotes ? (
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.5 }}
            className="flex flex-col items-center justify-center py-16"
          >
            <div className="w-24 h-24 rounded-full bg-[#1C1C1E] border-2 border-[#2A2A2E] flex items-center justify-center mb-6">
              <FileText className="w-12 h-12 text-[#7B61FF]" />
            </div>
            <h2 className="text-white text-xl mb-3">No notes yet</h2>
            <p className="text-[#A1A1AA] text-center max-w-xs mb-8">
              Start capturing your thoughts, reflections, and insights
            </p>
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={onCreateNote}
              className="px-6 py-3 bg-gradient-to-r from-[#7B61FF] to-[#A78BFA] rounded-[16px] text-white font-medium shadow-lg shadow-[#7B61FF]/30"
            >
              Create your first note
            </motion.button>
          </motion.div>
        ) : filteredNotes.length === 0 ? (
          // Search results empty
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.5 }}
            className="flex flex-col items-center justify-center py-12"
          >
            <div className="w-24 h-24 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center mb-6 shadow-2xl shadow-[#7B61FF]/20">
              <Search className="w-12 h-12 text-white" />
            </div>
            <h2 className="text-white text-xl mb-3">No notes found</h2>
            <p className="text-[#A1A1AA] text-center max-w-xs">
              Try adjusting your search or create a new note
            </p>
          </motion.div>
        ) : (
          // Notes List
          <div className="space-y-3">
            {filteredNotes.map((note, idx) => (
              <motion.button
                key={note.id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: idx * 0.05, duration: 0.4 }}
                whileHover={{ scale: 1.02, x: 4 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => handleNoteClick(note.id)}
                className="w-full bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] hover:border-[#7B61FF]/30 transition-all text-left"
              >
                <div className="flex items-start gap-3">
                  <div className="flex-1 min-w-0">
                    {/* Date */}
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs text-[#A1A1AA]">{note.date}</span>
                      {note.attachments.length > 0 && (
                        <div className="flex gap-1">
                          {note.attachments.map((attachment, i) => (
                            <div
                              key={i}
                              className="w-1.5 h-1.5 rounded-full bg-[#7B61FF]"
                            />
                          ))}
                        </div>
                      )}
                    </div>

                    {/* Title */}
                    {note.title && (
                      <h3 className="text-white mb-2">{note.title}</h3>
                    )}

                    {/* Preview */}
                    <p className="text-[#A1A1AA] text-sm line-clamp-2 leading-relaxed">
                      {note.content}
                    </p>
                  </div>

                  {/* Chevron */}
                  <ChevronRight className="w-5 h-5 text-[#A1A1AA] flex-shrink-0 mt-1" />
                </div>
              </motion.button>
            ))}
          </div>
        )}
      </div>

      {/* Floating Action Button */}
      <motion.button
        initial={{ opacity: 0, scale: 0 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ delay: 0.5, type: 'spring', stiffness: 300, damping: 20 }}
        whileHover={{ scale: 1.1 }}
        whileTap={{ scale: 0.9 }}
        onClick={onCreateNote}
        className="fixed bottom-24 right-6 w-14 h-14 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] shadow-2xl shadow-[#7B61FF]/40 flex items-center justify-center z-10"
      >
        <Plus className="w-6 h-6 text-white" />
      </motion.button>
    </div>
  );
}