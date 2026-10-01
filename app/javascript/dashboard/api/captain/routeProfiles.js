import ApiClient from '../ApiClient';

class CaptainRouteProfilesAPI extends ApiClient {
  constructor() {
    super('captain/route_profiles', { accountScoped: true });
  }

  save(routeKey, data) {
    return this.create({ route_key: routeKey, ...data });
  }
}

export default new CaptainRouteProfilesAPI();
