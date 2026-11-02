import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  conversations: {},
  directConversation: false,
  cardPreview: null,
  meta: {
    userLastSeenAt: undefined,
    showSuggestedQuestions: null,
  },
  uiFlags: {
    allMessagesLoaded: false,
    isFetchingList: false,
    isAgentTyping: false,
    isCreating: false,
  },
  lastMessageId: null,
  pendingCustomAttributes: {},
  pendingLabels: [],
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
