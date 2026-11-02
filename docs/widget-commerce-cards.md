# Website widget commerce cards

After `chatwoot:ready`, call `window.$chatwoot.openConversation(card)` to open the conversation directly and show an optional card preview above the input. The visitor can send or dismiss it. Call `setConversationCustomAttributes` separately to associate context with the conversation. On a new conversation, pending attributes are saved with the first message.

The host can also send a card on behalf of the visitor:

```js
window.$chatwoot.sendCard({
  type: 'product',
  title: 'Headphones',
  productId: 'g1001',
  price: '¥499.00',
  imageUrl: 'https://example.com/products/g1001.jpg',
  action: { type: 'miniapp', path: '/pages/goods/index?id=g1001' },
});
```

An order card uses `type: 'order'` and also requires `orderId` and `price`. Both card types require `title`, `productId`, and an HTTP(S) `imageUrl`. `action` is optional; it is either `{ type: 'miniapp', path: '/pages/...' }` or `{ type: 'url', url: 'https://...' }`. A card is a visitor message and creates a conversation if necessary. As with other visitor messages, sending is prohibited when the inbox disallows replies to resolved conversations.

The host handles clicks, choosing navigation appropriate to its environment:

```js
window.addEventListener('chatwoot:card-click', event => {
  const action = event.detail;
  if (action.type === 'miniapp') {
    wx.miniProgram.navigateTo({ url: action.path });
  } else if (action.type === 'url') {
    window.location.assign(action.url);
  }
});
```

For a WeChat web-view, load the WeChat JS SDK in the host page and configure the required business domain. Use `wx.miniProgram.navigateTo` for pages in the current mini program; web-view `postMessage` is not a real-time navigation bridge. Validate destinations against the host application's own policies before navigating.

An authenticated agent or integration can send an outgoing card using `POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/messages` and the usual account API token:

```json
{
  "message_type": "outgoing",
  "content_type": "cards",
  "content": "Order M20261027001",
  "content_attributes": {
    "items": [{
      "type": "order",
      "title": "Order M20261027001",
      "order_id": "M20261027001",
      "product_id": "g1001",
      "price": "¥499.00",
      "media_url": "https://example.com/products/g1001.jpg",
      "action": { "type": "url", "url": "https://example.com/orders/M20261027001" }
    }]
  }
}
```

`content` is the text used by previews and notifications. The API uses snake_case fields, unlike the SDK. Existing bot cards remain supported. Set suggested questions under the website inbox settings, one per line. They appear as a card at the start of a new conversation during the current page session. The card displays three questions at a time, and “Show more” cycles through configured questions in order. Selecting one sends it as a normal visitor message; the card itself is not stored as a message.
