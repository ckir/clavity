# Clavity Marketing & Beta KPI Metrics

Definitions, tracking methodologies, and target baselines for measuring developer acquisition, beta activity, and commercial interest.

## 1. Funnel Metric Definitions & Targets

| Metric | Definition | Measurement Source | Public Beta Target (90 Days) |
|---|---|---|---|
| **Unique Visitors** | Distinct browser sessions visiting the website within a 30-day window. | Website Analytics (`page_view`) | 5,000 |
| **Traffic Source Distribution** | Inbound referral channels categorized by source (GitHub, HN, Reddit, Social, Direct). | UTM parameters & HTTP Referrer | >= 40% Community / Referrals |
| **CTA Click-Through Rate (CTR)** | Percentage of unique visitors clicking a primary beta CTA or install trigger. | Website Analytics (`beta_cta_clicked` / visitors) | >= 12% |
| **GitHub Inbound Referrals** | Outbound clicks from website to the GitHub repository / releases page. | Website Analytics (`github_clicked`) | >= 1,500 clicks |
| **Beta Registrations** | Validated submissions through the optional beta interest intake form. | Intake Database / Form Webhook | 250 verified leads |
| **Successful Installations** | Verified installs of `clavity-dotnet` or `clavity-classic`. | GitHub Release Download Counters & Plugin Marketplace telemetry | >= 500 installations |
| **Active Testers** | Developers executing multi-agent tasks on a weekly basis. | Qualitative feedback / GitHub Discussions activity | >= 50 active developers |
| **Returning Users** | Beta registrants or community members providing ongoing feedback or bug reports. | Issue tracker / Discussion authors | >= 25 recurring contributors |
| **Commercial Prospects** | Leads indicating team size >= 5 and interest in an enterprise tier. | Beta Form Field (`has_commercial_interest`) | >= 20 qualified organizations |

## 2. Telemetry Boundaries & Non-Intrusive Estimation

Because Clavity intentionally avoids invasive desktop telemetry, developer usage metrics are estimated using ethical proxy indicators:
- **Binary Asset Downloads:** Tracking download counts of `clavity-ls` binaries attached to GitHub releases.
- **Plugin Marketplace Registrations:** Aggregated anonymous installation counts reported by the Claude plugin marketplace ecosystem.
- **GitHub Engagement:** Star velocity, fork count, and Discussion thread participation.
- **Issue Activity:** High-quality issue submissions citing specific session logs or test audit outputs.

## 3. Metric Review Cadence

- **Weekly Operational Review:** Monitor web traffic spikes following article publications and community announcements.
- **Monthly Cohort Review:** Evaluate beta form submissions, qualitative tester sentiment, and conversion rates from Show HN / Reddit campaigns.
- **Quarterly Commercial Assessment:** Review commercial prospect volume to determine whether the paid pilot phase can be initiated.
